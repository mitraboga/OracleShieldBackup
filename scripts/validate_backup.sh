#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

main() {
  init_job "validate_backup" "validation" "${STAGING_DIR}"
  enable_failure_trap

  run_rman_template "restore_database.rman"

  write_run_summary "SUCCESS" "RMAN restore validation completed"
  log "INFO" "Backup validation completed successfully"
}

main "$@"

