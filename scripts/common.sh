#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_DEFAULT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${BACKUP_CONFIG:-${PROJECT_ROOT_DEFAULT}/config/backup.conf}"

if [[ ! -r "${CONFIG_FILE}" ]]; then
  echo "OracleShieldBackup config is not readable: ${CONFIG_FILE}" >&2
  exit 78
fi

# shellcheck source=../config/backup.conf
source "${CONFIG_FILE}"

PROJECT_ROOT="${PROJECT_ROOT:-${PROJECT_ROOT_DEFAULT}}"
BACKUP_ROOT="${BACKUP_ROOT:-/u02/oracle_backups}"
RMAN_BACKUP_DIR="${RMAN_BACKUP_DIR:-${BACKUP_ROOT}/rman}"
ARCHIVE_BACKUP_DIR="${ARCHIVE_BACKUP_DIR:-${BACKUP_ROOT}/archivelog}"
STAGING_DIR="${STAGING_DIR:-${BACKUP_ROOT}/staging}"
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"
REPORT_DIR="${REPORT_DIR:-${PROJECT_ROOT}/reports}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
RMAN_CHANNELS="${RMAN_CHANNELS:-1}"
RMAN_TARGET="${RMAN_TARGET:-/}"
RMAN_RETENTION_POLICY="${RMAN_RETENTION_POLICY:-RECOVERY WINDOW OF 14 DAYS}"
ARCHIVELOG_DELETE_POLICY="${ARCHIVELOG_DELETE_POLICY:-BACKED UP 1 TIMES TO DEVICE TYPE DISK}"
INCREMENTAL_MODE="${INCREMENTAL_MODE:-CUMULATIVE}"
ENABLE_S3_UPLOAD="${ENABLE_S3_UPLOAD:-true}"
ENABLE_ALERTS="${ENABLE_ALERTS:-true}"
DRY_RUN="${DRY_RUN:-false}"

DATE_STAMP="$(date +%Y%m%d)"
TIME_STAMP="$(date +%Y%m%d_%H%M%S)"
RUN_ID=""
RUN_LOG=""
CURRENT_JOB=""
RMAN_OUTPUT_DIR=""
LAST_S3_URI=""

timestamp() {
  date '+%Y-%m-%d %H:%M:%S%z'
}

is_true() {
  case "${1:-}" in
    true|TRUE|True|1|yes|YES|Yes|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(timestamp)" "${level}" "$*"
}

die() {
  log "ERROR" "$*"
  return 1
}

host_name() {
  if [[ -n "${HOSTNAME_OVERRIDE:-}" ]]; then
    printf '%s\n' "${HOSTNAME_OVERRIDE}"
  elif command -v hostname >/dev/null 2>&1; then
    hostname -f 2>/dev/null || hostname
  else
    printf 'unknown-host\n'
  fi
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || die "Required command not found: ${command_name}"
}

detect_oracle_home() {
  local rman_path=""

  if [[ -n "${ORACLE_HOME:-}" && -x "${ORACLE_HOME}/bin/rman" ]]; then
    return 0
  fi

  rman_path="$(command -v rman 2>/dev/null || true)"
  if [[ -n "${rman_path}" ]]; then
    ORACLE_HOME="$(cd "$(dirname "${rman_path}")/.." && pwd)"
    return 0
  fi

  if [[ -d "/opt/oracle/product" ]]; then
    rman_path="$(find /opt/oracle/product -path '*/bin/rman' -type f -print -quit 2>/dev/null || true)"
    if [[ -n "${rman_path}" ]]; then
      ORACLE_HOME="$(cd "$(dirname "${rman_path}")/.." && pwd)"
      return 0
    fi
  fi
}

validate_oracle_config() {
  [[ -n "${ORACLE_SID:-}" ]] || die "ORACLE_SID is not set"
  [[ -n "${ORACLE_HOME:-}" ]] || die "ORACLE_HOME is not set"
  [[ -n "${RMAN_TARGET:-}" ]] || die "RMAN_TARGET is not set"
}

export_oracle_env() {
  detect_oracle_home
  validate_oracle_config
  export ORACLE_SID ORACLE_HOME RMAN_TARGET
  export NLS_DATE_FORMAT="${NLS_DATE_FORMAT:-YYYY-MM-DD HH24:MI:SS}"
  export PATH="${ORACLE_HOME}/bin:${PATH}"
}

init_job() {
  local job="$1"
  local category="${2:-${job}}"
  local output_base="${3:-${RMAN_BACKUP_DIR}}"

  CURRENT_JOB="${job}"
  DATE_STAMP="$(date +%Y%m%d)"
  TIME_STAMP="$(date +%Y%m%d_%H%M%S)"
  RUN_ID="${job}_${TIME_STAMP}"
  RUN_LOG="${LOG_DIR}/${RUN_ID}.log"
  RMAN_OUTPUT_DIR="${output_base}/${ORACLE_SID}/${category}/${DATE_STAMP}"

  mkdir -p "${LOG_DIR}" "${REPORT_DIR}" "${STAGING_DIR}/${RUN_ID}" "${RMAN_OUTPUT_DIR}"
  exec > >(tee -a "${RUN_LOG}") 2>&1

  log "INFO" "Starting ${CURRENT_JOB} run ${RUN_ID}"
  log "INFO" "Host: $(host_name)"
  log "INFO" "Config: ${CONFIG_FILE}"
  log "INFO" "Output directory: ${RMAN_OUTPUT_DIR}"
}

summary_field() {
  local value="${1:-}"
  value="${value//$'\t'/ }"
  value="${value//$'\n'/ }"
  printf '%s' "${value}"
}

write_run_summary() {
  local status="$1"
  local message="${2:-}"
  local summary_file="${REPORT_DIR}/backup_runs.tsv"

  mkdir -p "${REPORT_DIR}"
  if [[ ! -f "${summary_file}" ]]; then
    printf 'timestamp\trun_id\tjob\tstatus\toracle_sid\thost\toutput_dir\tlog_file\ts3_uri\tmessage\n' > "${summary_file}"
  fi

  {
    summary_field "$(timestamp)"; printf '\t'
    summary_field "${RUN_ID:-unknown}"; printf '\t'
    summary_field "${CURRENT_JOB:-unknown}"; printf '\t'
    summary_field "${status}"; printf '\t'
    summary_field "${ORACLE_SID:-unknown}"; printf '\t'
    summary_field "$(host_name)"; printf '\t'
    summary_field "${RMAN_OUTPUT_DIR:-}"; printf '\t'
    summary_field "${RUN_LOG:-}"; printf '\t'
    summary_field "${LAST_S3_URI:-}"; printf '\t'
    summary_field "${message}"
    printf '\n'
  } >> "${summary_file}"
}

build_aws_args() {
  AWS_ARGS=()
  [[ -n "${AWS_PROFILE:-}" ]] && AWS_ARGS+=(--profile "${AWS_PROFILE}")
  [[ -n "${AWS_REGION:-}" ]] && AWS_ARGS+=(--region "${AWS_REGION}")
}

join_s3_uri() {
  local subpath="${1:-}"
  local uri="${S3_BUCKET%/}"

  [[ -n "${S3_PREFIX:-}" ]] && uri="${uri}/${S3_PREFIX#/}"
  [[ -n "${subpath}" ]] && uri="${uri}/${subpath#/}"
  printf '%s\n' "${uri}"
}

send_alert() {
  local subject="$1"
  local body="$2"

  is_true "${ENABLE_ALERTS}" || return 0

  if [[ -n "${SNS_TOPIC_ARN:-}" ]] && command -v aws >/dev/null 2>&1; then
    build_aws_args
    aws "${AWS_ARGS[@]}" sns publish \
      --topic-arn "${SNS_TOPIC_ARN}" \
      --subject "${subject}" \
      --message "${body}" >/dev/null || log "WARN" "AWS SNS alert publish failed"
  fi

  if [[ -n "${ALERT_EMAIL:-}" ]] && command -v "${MAIL_CMD:-mailx}" >/dev/null 2>&1; then
    printf '%s\n' "${body}" | "${MAIL_CMD:-mailx}" -s "${subject}" "${ALERT_EMAIL}" || log "WARN" "Email alert failed"
  elif [[ -n "${ALERT_EMAIL:-}" ]] && command -v mail >/dev/null 2>&1; then
    printf '%s\n' "${body}" | mail -s "${subject}" "${ALERT_EMAIL}" || log "WARN" "Email alert failed"
  else
    log "WARN" "Alerts enabled but no usable mail command or SNS topic is configured"
  fi
}

handle_failure() {
  local exit_code=$?
  local line_no="${1:-unknown}"
  trap - ERR

  local subject="[OracleShieldBackup] ${CURRENT_JOB:-backup} failed on $(host_name)"
  local body
  body="$(cat <<BODY
Job: ${CURRENT_JOB:-unknown}
Run ID: ${RUN_ID:-unknown}
Oracle SID: ${ORACLE_SID:-unknown}
Host: $(host_name)
Exit code: ${exit_code}
Line: ${line_no}
Log: ${RUN_LOG:-not initialized}
Output: ${RMAN_OUTPUT_DIR:-not initialized}
BODY
)"

  log "ERROR" "${CURRENT_JOB:-backup} failed at line ${line_no} with exit code ${exit_code}"
  write_run_summary "FAILED" "Failed at line ${line_no} with exit code ${exit_code}" || true
  send_alert "${subject}" "${body}" || true
  exit "${exit_code}"
}

enable_failure_trap() {
  trap 'handle_failure ${LINENO}' ERR
}

render_rman_template() {
  local template="$1"
  local output="$2"
  local content

  [[ -r "${template}" ]] || die "RMAN template not readable: ${template}"
  content="$(<"${template}")"
  content="${content//__PROJECT_ROOT__/${PROJECT_ROOT}}"
  content="${content//__ORACLE_SID__/${ORACLE_SID}}"
  content="${content//__BACKUP_ROOT__/${BACKUP_ROOT}}"
  content="${content//__RMAN_BACKUP_DIR__/${RMAN_BACKUP_DIR}}"
  content="${content//__ARCHIVE_BACKUP_DIR__/${ARCHIVE_BACKUP_DIR}}"
  content="${content//__RMAN_OUTPUT_DIR__/${RMAN_OUTPUT_DIR}}"
  content="${content//__DATE_STAMP__/${DATE_STAMP}}"
  content="${content//__TIME_STAMP__/${TIME_STAMP}}"
  content="${content//__RUN_ID__/${RUN_ID}}"
  content="${content//__RMAN_CHANNELS__/${RMAN_CHANNELS}}"
  content="${content//__RMAN_RETENTION_POLICY__/${RMAN_RETENTION_POLICY}}"
  content="${content//__ARCHIVELOG_DELETE_POLICY__/${ARCHIVELOG_DELETE_POLICY}}"
  content="${content//__INCREMENTAL_MODE__/${INCREMENTAL_MODE}}"

  printf '%s\n' "${content}" > "${output}"
}

run_rman_template() {
  local template_name="$1"
  local template="${PROJECT_ROOT}/rman/${template_name}"
  local runtime_cmd="${STAGING_DIR}/${RUN_ID}/${template_name}.rendered"
  local rman_log="${LOG_DIR}/${RUN_ID}.rman.log"

  export_oracle_env
  require_command rman
  mkdir -p "$(dirname "${runtime_cmd}")"
  render_rman_template "${template}" "${runtime_cmd}"

  log "INFO" "Running RMAN template ${template_name}"
  rman target "${RMAN_TARGET}" cmdfile "${runtime_cmd}" log "${rman_log}"
  log "INFO" "RMAN completed successfully. RMAN log: ${rman_log}"
}

generate_manifest() {
  local source_dir="$1"
  local metadata_file="${source_dir}/RUN_METADATA.txt"
  local manifest_file="${source_dir}/MANIFEST.sha256"

  [[ -d "${source_dir}" ]] || die "Manifest source directory not found: ${source_dir}"

  cat > "${metadata_file}" <<METADATA
run_id=${RUN_ID}
job=${CURRENT_JOB}
oracle_sid=${ORACLE_SID}
host=$(host_name)
created_at=$(timestamp)
output_dir=${source_dir}
METADATA

  if command -v sha256sum >/dev/null 2>&1; then
    (cd "${source_dir}" && find . -type f ! -name 'MANIFEST.sha256' -print0 | sort -z | xargs -0r sha256sum > "${manifest_file}")
    log "INFO" "Wrote checksum manifest: ${manifest_file}"
  else
    log "WARN" "sha256sum not found; checksum manifest skipped"
  fi
}

upload_backup_directory() {
  local source_dir="$1"
  local s3_subpath="$2"

  if ! is_true "${ENABLE_S3_UPLOAD}"; then
    log "WARN" "S3 upload disabled by ENABLE_S3_UPLOAD=false"
    return 0
  fi

  [[ -d "${source_dir}" ]] || die "S3 upload source directory not found: ${source_dir}"
  [[ -n "${S3_BUCKET:-}" ]] || die "S3_BUCKET is not configured"

  require_command aws
  build_aws_args
  LAST_S3_URI="$(join_s3_uri "${s3_subpath}")"

  local sync_args=(s3 sync "${source_dir}" "${LAST_S3_URI}" --only-show-errors --storage-class "${AWS_STORAGE_CLASS:-STANDARD_IA}")
  [[ -n "${S3_SSE:-}" ]] && sync_args+=(--sse "${S3_SSE}")
  is_true "${DRY_RUN}" && sync_args+=(--dryrun)

  log "INFO" "Uploading ${source_dir} to ${LAST_S3_URI}"
  aws "${AWS_ARGS[@]}" "${sync_args[@]}"
}

upload_backup_file() {
  local source_file="$1"
  local s3_subpath="$2"

  if ! is_true "${ENABLE_S3_UPLOAD}"; then
    log "WARN" "S3 upload disabled by ENABLE_S3_UPLOAD=false"
    return 0
  fi

  [[ -f "${source_file}" ]] || die "S3 upload source file not found: ${source_file}"
  [[ -n "${S3_BUCKET:-}" ]] || die "S3_BUCKET is not configured"

  require_command aws
  build_aws_args
  LAST_S3_URI="$(join_s3_uri "${s3_subpath}")"

  local cp_args=(s3 cp "${source_file}" "${LAST_S3_URI}" --only-show-errors --storage-class "${AWS_STORAGE_CLASS:-STANDARD_IA}")
  [[ -n "${S3_SSE:-}" ]] && cp_args+=(--sse "${S3_SSE}")
  is_true "${DRY_RUN}" && cp_args+=(--dryrun)

  log "INFO" "Uploading ${source_file} to ${LAST_S3_URI}"
  aws "${AWS_ARGS[@]}" "${cp_args[@]}"
}

assert_safe_cleanup_path() {
  local path="$1"
  [[ -n "${path}" ]] || die "Refusing to clean an empty path"
  [[ "${path}" != "/" ]] || die "Refusing to clean /"
  [[ "${path}" != "." ]] || die "Refusing to clean ."
}

cleanup_local_retention() {
  local days="${RETENTION_DAYS}"
  local log_days="${LOG_RETENTION_DAYS}"
  local dir

  [[ "${days}" =~ ^[0-9]+$ ]] || die "RETENTION_DAYS must be numeric"
  [[ "${log_days}" =~ ^[0-9]+$ ]] || die "LOG_RETENTION_DAYS must be numeric"
  [[ "${days}" -ge 1 ]] || die "RETENTION_DAYS must be at least 1"
  [[ "${log_days}" -ge 1 ]] || die "LOG_RETENTION_DAYS must be at least 1"

  for dir in "${RMAN_BACKUP_DIR}/${ORACLE_SID}" "${ARCHIVE_BACKUP_DIR}/${ORACLE_SID}" "${STAGING_DIR}"; do
    [[ -d "${dir}" ]] || continue
    assert_safe_cleanup_path "${dir}"
    log "INFO" "Removing local files older than ${days} days under ${dir}"
    find "${dir}" -type f -mtime "+${days}" -print -delete
    find "${dir}" -type d -empty -print -delete
  done

  if [[ -d "${LOG_DIR}" ]]; then
    assert_safe_cleanup_path "${LOG_DIR}"
    log "INFO" "Removing logs older than ${log_days} days under ${LOG_DIR}"
    find "${LOG_DIR}" -type f -name '*.log' -mtime "+${log_days}" -print -delete
  fi
}
