#!/usr/bin/env bash
set -Eeuo pipefail

COMMAND="${1:-status}"
SERVICE="oracle-db"
CONTAINER_CONFIG="/opt/oracle/oracle-shield/config/docker-demo.conf"
SCRIPT_ROOT="/opt/oracle/oracle-shield/scripts"

run_backup_script() {
  local script_name="$1"
  docker compose exec "${SERVICE}" bash -lc "BACKUP_CONFIG=${CONTAINER_CONFIG} bash ${SCRIPT_ROOT}/${script_name}"
}

case "${COMMAND}" in
  up)
    docker compose up -d
    docker compose ps
    ;;
  status)
    docker compose ps
    ;;
  logs)
    docker compose logs --tail 80 -f "${SERVICE}"
    ;;
  full)
    run_backup_script "full_backup.sh"
    ;;
  incremental)
    run_backup_script "incremental_backup.sh"
    ;;
  archive)
    run_backup_script "archive_backup.sh"
    ;;
  validate)
    run_backup_script "validate_backup.sh"
    ;;
  restore-test)
    run_backup_script "restore_test.sh"
    ;;
  cleanup)
    run_backup_script "cleanup_old_backups.sh"
    ;;
  report)
    run_backup_script "generate_report.sh"
    ;;
  shell)
    docker compose exec "${SERVICE}" bash
    ;;
  down)
    docker compose down
    ;;
  *)
    echo "Usage: $0 {up|status|logs|full|incremental|archive|validate|restore-test|cleanup|report|shell|down}" >&2
    exit 64
    ;;
esac

