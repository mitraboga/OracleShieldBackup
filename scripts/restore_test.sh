#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

main() {
  init_job "restore_test" "restore_test" "${STAGING_DIR}"
  enable_failure_trap

  case "${RESTORE_TEST_MODE:-validate}" in
    validate)
      log "INFO" "Running non-destructive RMAN restore validation"
      run_rman_template "restore_database.rman"
      ;;
    *)
      die "Unsupported RESTORE_TEST_MODE=${RESTORE_TEST_MODE}. Use validate, or follow docs/disaster_recovery_plan.md for a controlled restore."
      ;;
  esac

  write_run_summary "SUCCESS" "Recovery readiness test completed"
  log "INFO" "Restore test completed successfully"
}

main "$@"

