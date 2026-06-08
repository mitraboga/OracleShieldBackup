#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

main() {
  init_job "full_backup" "full" "${RMAN_BACKUP_DIR}"
  enable_failure_trap

  run_rman_template "full_backup.rman"
  generate_manifest "${RMAN_OUTPUT_DIR}"
  upload_backup_directory "${RMAN_OUTPUT_DIR}" "database/full/${DATE_STAMP}"
  cleanup_local_retention

  write_run_summary "SUCCESS" "Full RMAN backup completed"
  log "INFO" "Full backup completed successfully"
}

main "$@"

