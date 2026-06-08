#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

main() {
  init_job "archive_backup" "archive" "${ARCHIVE_BACKUP_DIR}"
  enable_failure_trap

  run_rman_template "archive_backup.rman"
  generate_manifest "${RMAN_OUTPUT_DIR}"
  upload_backup_directory "${RMAN_OUTPUT_DIR}" "archivelog/${DATE_STAMP}"
  cleanup_local_retention

  write_run_summary "SUCCESS" "Archive log backup completed"
  log "INFO" "Archive log backup completed successfully"
}

main "$@"

