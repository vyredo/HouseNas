#!/bin/bash
# configure.sh - Post-install configuration for Nextcloud Docker stack
# - Waits for Nextcloud to be ready
# - Enables Redis caching via occ
# - Enables 2FA (TOTP) app
# - Installs recommended apps for previews
# - Runs basic security checks and preview generation
#
# Usage: ./configure.sh
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
print_err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

COMPOSE_CMD="docker compose" # assumes Docker Compose plugin
NEXTCLOUD_HOST="http://localhost:8081"
MAX_WAIT_SECONDS=600
SLEEP_INTERVAL=5

# Ensure docker compose is available
if ! command -v docker >/dev/null 2>&1; then
  print_err "docker is not installed. Run setup.sh first."
  exit 1
fi

# Load .env if present to provide values like REDIS_PASSWORD
if [ -f .env ]; then
  # shellcheck disable=SC1091
  set -o allexport
  source .env
  set +o allexport
fi

print_info "Waiting for Nextcloud to become ready at ${NEXTCLOUD_HOST} ..."

elapsed=0
while true; do
  if curl -fsS "${NEXTCLOUD_HOST}/status.php" >/dev/null 2>&1; then
    print_info "Nextcloud responded to healthcheck"
    break
  fi
  if [ "$elapsed" -ge "$MAX_WAIT_SECONDS" ]; then
    print_err "Timeout waiting for Nextcloud to start (waited ${MAX_WAIT_SECONDS}s)"
    exit 2
  fi
  sleep "$SLEEP_INTERVAL"
  elapsed=$((elapsed + SLEEP_INTERVAL))
done

# Helper to run occ commands as www-data inside the nextcloud container
occ() {
  ${COMPOSE_CMD} exec -u www-data nextcloud php occ "$@"
}

print_info "Configuring Redis as Nextcloud memcache backend..."
# Set memcache and Redis connection settings
# Use try/catch like approach to avoid failing if settings already set
set +e
occ config:system:set memcache.local --value '\OC\Memcache\Redis'
occ config:system:set memcache.locking --value '\OC\Memcache\Redis'

# Set Redis connection details (host and port)
if [ -n "${REDIS_PASSWORD-}" ]; then
  occ config:system:set redis host --value redis
  occ config:system:set redis port --value 6379
  occ config:system:set redis password --value "${REDIS_PASSWORD}"
else
  occ config:system:set redis host --value redis
  occ config:system:set redis port --value 6379
fi
set -e

print_info "Enabling Two-Factor Authentication (TOTP) app..."
# Enable twofactor_totp (safe to run if already enabled)
set +e
occ app:enable twofactor_totp
set -e

print_info "Installing recommended apps for previews and editing..."

# Recommended apps: previewgenerator, files_texteditor, photos, viewer
# Some app names may vary by Nextcloud version; ignore failures to avoid stopping script
set +e
occ app:install previewgenerator || true
occ app:install files_texteditor || occ app:install text || true
occ app:install photos || true
occ app:install viewer || true
set -e

print_info "Enabling preview generator and generating initial previews (may take time)..."

# Enable background preview generation for better performance
set +e
occ config:app:set preview -c background -v 1 || true
set -e

# Run one-time preview generation for existing files (non-blocking)
print_info "Triggering preview generation (in background) via cron container..."
${COMPOSE_CMD} exec -T nextcloud-cron sh -c "php /var/www/html/occ preview:pre-generate" || print_warn "preview:pre-generate returned non-zero; previews will generate on demand or via background job"

print_info "Running security scan (php occ security:check)..."
set +e
occ security:check || print_warn "security:check returned non-zero; check logs for details"
set -e

print_info "Fixing file permissions for data directory (host-owned UID 1000:GID 1000 required)..."
# Attempt to set permissions inside container (best-effort)
${COMPOSE_CMD} exec -u root nextcloud chown -R 1000:1000 /var/www/html/data || print_warn "Could not chown /var/www/html/data inside container; ensure host path /mnt/storage/nextcloud is owned by 1000:1000"

print_info "Configuration complete."

# Display access info
if [ -f .env ]; then
  ADMIN_USER="${NEXTCLOUD_ADMIN_USER-admin}"
  ADMIN_PASS="${NEXTCLOUD_ADMIN_PASSWORD-}"
  if [ -n "$ADMIN_PASS" ]; then
    echo
    print_info "Nextcloud access:"
    echo "  Remote URL: https://nas.soundsgoodlab.sg"
    echo "  Local URL:  http://<radxa-ip>:8081 or http://localhost:8081 (if running locally)"
    echo "  Admin user: ${ADMIN_USER}"
    echo "  Admin password: ${ADMIN_PASS}"
    echo
  else
    print_warn "Admin password not found in .env. Check your .env file."
  fi
else
  print_warn ".env file not found; cannot display admin credentials."
fi

echo
print_info "Suggested next steps:"
echo " - Log in and create a regular (non-admin) user for daily use."
echo " - Enable HTTPS/Strict-Transport-Security in Cloudflare dashboard."
echo " - Configure external storage and quota management as needed."
echo
print_info "You can view Nextcloud logs with:"
echo "  docker compose logs -f nextcloud"