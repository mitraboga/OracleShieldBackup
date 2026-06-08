#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

main() {
  local runs_file="${REPORT_DIR}/backup_runs.tsv"
  local dashboard_file="${REPORT_DIR}/dashboard.md"
  local total_runs=0
  local failed_runs=0
  local success_runs=0
  local last_status="NO DATA"
  local last_job="NO DATA"
  local last_time="NO DATA"

  init_job "generate_report" "report" "${STAGING_DIR}"
  enable_failure_trap

  if [[ -f "${runs_file}" ]]; then
    total_runs="$(awk -F '\t' 'NR > 1 {count++} END {print count + 0}' "${runs_file}")"
    failed_runs="$(awk -F '\t' 'NR > 1 && $4 == "FAILED" {count++} END {print count + 0}' "${runs_file}")"
    success_runs="$(awk -F '\t' 'NR > 1 && $4 == "SUCCESS" {count++} END {print count + 0}' "${runs_file}")"
    last_status="$(awk -F '\t' 'NR > 1 {status=$4} END {print status ? status : "NO DATA"}' "${runs_file}")"
    last_job="$(awk -F '\t' 'NR > 1 {job=$3} END {print job ? job : "NO DATA"}' "${runs_file}")"
    last_time="$(awk -F '\t' 'NR > 1 {time=$1} END {print time ? time : "NO DATA"}' "${runs_file}")"
  fi

  {
    printf '# OracleShieldBackup Dashboard\n\n'
    printf 'Generated: %s\n\n' "$(timestamp)"
    printf '| Metric | Value |\n'
    printf '| --- | --- |\n'
    printf '| Oracle SID | %s |\n' "${ORACLE_SID}"
    printf '| Host | %s |\n' "$(host_name)"
    printf '| Last run | %s |\n' "${last_time}"
    printf '| Last job | %s |\n' "${last_job}"
    printf '| Last status | %s |\n' "${last_status}"
    printf '| Successful runs | %s |\n' "${success_runs}"
    printf '| Failed runs | %s |\n' "${failed_runs}"
    printf '| Total recorded runs | %s |\n' "${total_runs}"
    printf '| S3 target | %s |\n\n' "$(join_s3_uri "")"
    printf '## Recent Runs\n\n'
    printf '| Timestamp | Job | Status | Output | S3 URI |\n'
    printf '| --- | --- | --- | --- | --- |\n'
    if [[ -f "${runs_file}" ]]; then
      tail -n 10 "${runs_file}" | awk -F '\t' 'NR > 1 || $1 != "timestamp" {printf "| %s | %s | %s | `%s` | `%s` |\n", $1, $3, $4, $7, $9}'
    else
      printf '| No runs recorded |  |  |  |  |\n'
    fi
  } > "${dashboard_file}"

  write_run_summary "SUCCESS" "Dashboard report generated"
  log "INFO" "Dashboard report written to ${dashboard_file}"
}

main "$@"

