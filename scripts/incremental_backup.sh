#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

main() {
  init_job "incremental_backup" "incremental" "${RMAN_BACKUP_DIR}"
  enable_failure_trap

  run_rman_template "incremental_backup.rman"
  generate_manifest "${RMAN_OUTPUT_DIR}"
  upload_backup_directory "${RMAN_OUTPUT_DIR}" "database/incremental/${DATE_STAMP}"
  cleanup_local_retention

  write_run_summary "SUCCESS" "Incremental RMAN backup completed"
  log "INFO" "Incremental backup completed successfully"
}

main "$@"

