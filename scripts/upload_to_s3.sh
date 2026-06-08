#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<USAGE
Usage: $0 <local-file-or-directory> [s3-subpath]

Examples:
  $0 /u02/oracle_backups/rman/ORCLCDB/full/20260523 database/full/20260523
  $0 /u02/oracle_backups/rman/ORCLCDB/full/20260523/MANIFEST.sha256 manifests/full-20260523.sha256
USAGE
}

main() {
  local source_path="${1:-}"
  local s3_subpath="${2:-}"

  [[ -n "${source_path}" ]] || { usage; exit 64; }
  [[ -e "${source_path}" ]] || die "Source path not found: ${source_path}"

  init_job "upload_to_s3" "manual_upload" "${STAGING_DIR}"
  enable_failure_trap

  if [[ -z "${s3_subpath}" ]]; then
    s3_subpath="manual/$(basename "${source_path}")"
  fi

  if [[ -d "${source_path}" ]]; then
    upload_backup_directory "${source_path}" "${s3_subpath}"
  else
    upload_backup_file "${source_path}" "${s3_subpath}"
  fi

  write_run_summary "SUCCESS" "Manual S3 upload completed"
  log "INFO" "Manual S3 upload completed successfully"
}

main "$@"

