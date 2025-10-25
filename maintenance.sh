#!/bin/bash
# maintenance.sh - Maintenance utilities for Nextcloud NAS Docker stack
# Usage: sudo ./maintenance.sh <command>
# Commands:
#   update          - Pull latest images and recreate containers
#   backup          - Backup Nextcloud config, data and PostgreSQL database
#   status          - Show docker compose ps and recent logs
#   maintenance on  - Enable Nextcloud maintenance mode
#   maintenance off - Disable Nextcloud maintenance mode
#   restart <svc>   - Restart a specific service (e.g., nextcloud, nextcloud-db, redis, cloudflared)
#   disk            - Show disk usage for storage paths
#   help            - Show this help
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BASE_DIR="${HOME}/nextcloud-nas"
BACKUP_DIR="${BASE_DIR}/backups"
COMPOSE_CMD="docker compose"

print_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
print_err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Ensure running from project root if it exists; otherwise continue
if [ -d "${BASE_DIR}" ]; then
  cd "${BASE_DIR}" || { print_err "Failed to cd to ${BASE_DIR}"; exit 2; }
else
  print_warn "Project directory ${BASE_DIR} does not exist. Continuing from $(pwd)"
fi

# Load .env if present
if [ -f .env ]; then
  # shellcheck disable=SC1091
  set -o allexport
  source .env
  set +o allexport
fi

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    print_err "docker is not installed or not in PATH. Run setup.sh first."
    exit 1
  fi
}

cmd_update() {
  require_docker
  print_info "Pulling latest images..."
  if ! ${COMPOSE_CMD} pull --quiet; then
    print_warn "docker compose pull returned non-zero; continuing with up -d"
  fi

  print_info "Recreating containers with latest images..."
  ${COMPOSE_CMD} up -d --remove-orphans
  print_info "Update complete. Use '${COMPOSE_CMD} ps' to verify status."
}

cmd_backup() {
  require_docker
  mkdir -p "${BACKUP_DIR}"
  ts=$(date -u +"%Y%m%dT%H%M%SZ")
  snapshot_dir="${BACKUP_DIR}/backup-${ts}"
  mkdir -p "${snapshot_dir}"

  print_info "Backing up Nextcloud configuration and database to ${snapshot_dir} ..."

  # 1) Dump PostgreSQL database using pg_dump from the postgres container
  if docker compose ps -q nextcloud-db >/dev/null 2>&1; then
    print_info "Dumping PostgreSQL database..."
    # Use NEXTCLOUD_DB_PASSWORD from .env if available
    if [ -n "${NEXTCLOUD_DB_PASSWORD-}" ]; then
      # Use docker exec and pg_dump; output redirected to host file
      if docker compose exec -T -e PGPASSWORD="${NEXTCLOUD_DB_PASSWORD}" nextcloud-db pg_dump -U "${NEXTCLOUD_DB_USER:-nextcloud}" "${NEXTCLOUD_DB_NAME:-nextcloud}" > "${snapshot_dir}/db-${ts}.sql"; then
        print_info "Database dump saved to ${snapshot_dir}/db-${ts}.sql"
      else
        print_warn "Database dump failed. Ensure the database container is healthy and credentials are correct."
      fi
    else
      print_warn "NEXTCLOUD_DB_PASSWORD not set in .env; skipping DB dump."
    fi
  else
    print_warn "Postgres container 'nextcloud-db' not running; skipping DB dump."
  fi

  # 2) Archive Nextcloud config and apps (./nextcloud/html/config and ./nextcloud/html/apps)
  if [ -d ./nextcloud/html ]; then
    print_info "Archiving Nextcloud app files and config..."
    tar -czf "${snapshot_dir}/nextcloud-html-${ts}.tar.gz" -C ./nextcloud html || print_warn "Failed to archive nextcloud/html"
  else
    print_warn "./nextcloud/html not found; skipping"
  fi

  # 3) Archive user data (/mnt/storage/nextcloud)
  if [ -d /mnt/storage/nextcloud ]; then
    print_info "Archiving user data (this may take time depending on size)..."
    tar -czf "${snapshot_dir}/data-${ts}.tar.gz" -C /mnt/storage nextcloud || print_warn "Failed to archive /mnt/storage/nextcloud"
  else
    print_warn "/mnt/storage/nextcloud not found; skipping data backup"
  fi

  print_info "Backup complete. Snapshots stored in ${snapshot_dir}"
  print_info "Tip: Move backups off-device to external storage or cloud for redundancy."
}

cmd_status() {
  require_docker
  print_info "Container status:"
  ${COMPOSE_CMD} ps
  echo
  print_info "Recent logs (last 200 lines):"
  ${COMPOSE_CMD} logs --tail=200
}

cmd_maintenance_on() {
  require_docker
  print_info "Enabling Nextcloud maintenance mode..."
  docker compose exec -u www-data nextcloud php occ maintenance:mode --on
  print_info "Maintenance mode enabled"
}

cmd_maintenance_off() {
  require_docker
  print_info "Disabling Nextcloud maintenance mode..."
  docker compose exec -u www-data nextcloud php occ maintenance:mode --off
  print_info "Maintenance mode disabled"
}

cmd_restart() {
  require_docker
  svc="${1:-}"
  if [ -z "$svc" ]; then
    print_err "Service name required. Usage: maintenance.sh restart <service>"
    exit 3
  fi
  print_info "Restarting service: ${svc}"
  ${COMPOSE_CMD} restart "${svc}"
  print_info "Restart command issued for ${svc}"
}

cmd_disk() {
  print_info "Disk usage for nextcloud data and project dirs:"
  du -sh /mnt/storage/nextcloud 2>/dev/null || print_warn "/mnt/storage/nextcloud not found"
  du -sh "${BASE_DIR}/nextcloud" 2>/dev/null || print_warn "${BASE_DIR}/nextcloud not found"
  print_info "Filesystem usage:"
  df -h .
}

cmd_help() {
  sed -n '1,120p' "$0" | sed -n '1,80p'
  echo
  echo "Examples:"
  echo "  sudo ./maintenance.sh backup"
  echo "  ./maintenance.sh update"
  echo "  ./maintenance.sh restart nextcloud"
}

main() {
  if [ $# -lt 1 ]; then
    cmd_help
    exit 0
  fi

  case "$1" in
    update)
      cmd_update
      ;;
    backup)
      cmd_backup
      ;;
    status)
      cmd_status
      ;;
    maintenance)
      if [ "${2-}" = "on" ]; then
        cmd_maintenance_on
      elif [ "${2-}" = "off" ]; then
        cmd_maintenance_off
      else
        print_err "Invalid maintenance option. Use 'on' or 'off'."
        exit 4
      fi
      ;;
    restart)
      shift
      cmd_restart "$@"
      ;;
    disk)
      cmd_disk
      ;;
    help|-h|--help)
      cmd_help
      ;;
    *)
      print_err "Unknown command: $1"
      cmd_help
      exit 5
      ;;
  esac
}

main "$@"