#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

main() {
  init_job "cleanup_old_backups" "cleanup" "${STAGING_DIR}"
  enable_failure_trap

  cleanup_local_retention

  write_run_summary "SUCCESS" "Local retention cleanup completed"
  log "INFO" "Cleanup completed successfully"
}

main "$@"

