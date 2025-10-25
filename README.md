# Nextcloud NAS (Radxa) — README

Overview

This repository contains a production-ready Docker Compose setup to run Nextcloud on an ARM64 Radxa device with Cloudflare Tunnel. The stack uses PostgreSQL, Redis, and Cloudflare Tunnel to provide secure, remotely-accessible file storage similar to Google Drive.

Components

- Nextcloud (web UI, syncing)
- PostgreSQL (database)
- Redis (cache)
- cloudflared (Cloudflare Tunnel)

Quick start

1. Review and edit the environment file: [`.env`](.env:1)
2. Run the setup script to install Docker, create directories and generate secrets:

   ```
   sudo bash ./setup.sh
   ```

3. When prompted, paste your Cloudflare Tunnel token.
4. Start services: (setup.sh runs this automatically)

   ```
   docker compose up -d
   ```

5. Run post-install configuration:

   ```
   ./configure.sh
   ```

Access URLs

- Remote (via Cloudflare): <https://nas.soundsgoodlab.sg>
- Local (on Radxa / LAN): http://<radxa-ip>:8081

Default account

- Admin user: value of `NEXTCLOUD_ADMIN_USER` in [`.env`](.env:1)
- Admin password: value of `NEXTCLOUD_ADMIN_PASSWORD` in [`.env`](.env:1)

Files in this project

- [`docker-compose.yml`](docker-compose.yml:1) — Docker Compose configuration (Nextcloud, db, redis, cloudflared, cron)
- [`setup.sh`](setup.sh:1) — Installation script (installs Docker, creates directories, generates .env and starts services)
- [`configure.sh`](configure.sh:1) — Post-install configuration (occ, Redis, 2FA, preview apps)
- [`maintenance.sh`](maintenance.sh:1) — Maintenance utilities (backup, update, status, maintenance mode)
- [`.env`](.env:1) — Environment variables (secrets). Do NOT commit this file.

Prerequisites & assumptions

- You have sudo access on the Radxa board.
- OS: Debian/Ubuntu-based (apt available).
- External storage mounted at `/mnt/storage` (the setup script will create `/mnt/storage/nextcloud` if missing).
- DNS for `soundsgoodlab.sg` is managed in Cloudflare.
- You already have a Cloudflare Tunnel token ready.

Security recommendations

- Use strong random passwords. Generate with:

  ```
  openssl rand -base64 32
  ```

- Keep `.env` private and do not commit it.
- Create a non-admin user for daily use.
- Enable Two-Factor Authentication (TOTP) for user accounts.
- Use Cloudflare Access or additional firewall rules if desired.

Cloudflare Tunnel notes

- The [`cloudflared` service is defined in `docker-compose.yml`](docker-compose.yml:1) and reads `CLOUDFLARE_TUNNEL_TOKEN` from `.env`.
- Configure the Tunnel in Cloudflare to forward `nas.soundsgoodlab.sg` to the Tunnel.
- Nextcloud environment variables set for tunnel compatibility:
  - `OVERWRITEPROTOCOL=https`
  - `OVERWRITEHOST=nas.soundsgoodlab.sg`
  - `TRUSTED_PROXIES=172.16.0.0/12`

Storage and permissions

- Application files: `./nextcloud/html` (persisted)
- Database files: `./nextcloud/db` (persisted)
- User files: `/mnt/storage/nextcloud` (must be owned by UID:GID 1000:1000)
- The setup script sets ownership: `sudo chown -R 1000:1000 /mnt/storage/nextcloud`

Client setup

- macOS (Homebrew):

  ```
  brew install --cask nextcloud
  ```

  Or download from: <https://nextcloud.com/install/#install-clients>
- Android: <https://play.google.com/store/apps/details?id=com.nextcloud.client>
- iOS: <https://apps.apple.com/app/nextcloud/id1125420102>

Management & common commands

- Start services:

  ```
  docker compose up -d
  ```

- Stop services:

  ```
  docker compose down
  ```

- View logs:

  ```
  docker compose logs -f
  ```

- Restart Nextcloud only:

  ```
  docker compose restart nextcloud
  ```

- Update images and recreate:

  ```
  docker compose pull && docker compose up -d
  ```

- Enter Nextcloud CLI (occ):

  ```
  docker compose exec -u www-data nextcloud php occ <command>
  ```

- Run post-install configuration:

  ```
  ./configure.sh
  ```

Backup procedure (recommended)

- Use [`maintenance.sh`](maintenance.sh:1) to create backups:

  ```
  sudo ./maintenance.sh backup
  ```

- Backup includes:
  - PostgreSQL dump
  - Archive of `./nextcloud/html` (apps/config)
  - Archive of `/mnt/storage/nextcloud` user data
- Store backups off-device (external drive or cloud storage).

Maintenance tasks

- Enable maintenance mode:

  ```
  sudo ./maintenance.sh maintenance on
  ```

- Disable maintenance mode:

  ```
  sudo ./maintenance.sh maintenance off
  ```

- Update stack:

  ```
  ./maintenance.sh update
  ```

Troubleshooting

- Check container health:

  ```
  docker compose ps
  ```

- Check Nextcloud health endpoint:

  ```
  curl -fsS http://localhost:8081/status.php
  ```

- If Nextcloud never finishes initial setup:
  - Ensure PostgreSQL is reachable and credentials in `.env` match.
  - Check logs: `docker compose logs nextcloud`
  - Ensure `/mnt/storage/nextcloud` is writable by UID 1000
- Reset admin password (run inside Nextcloud container):

  ```
  docker compose exec -u www-data nextcloud php occ user:resetpassword admin
  ```

File preview support

- The configuration installs preview and viewer apps to enable:
  - Images (JPG, PNG, GIF, SVG, WEBP)
  - Videos (MP4, AVI, MKV) — browser playback depends on codecs
  - PDFs — embedded PDF viewer
  - Office documents — Nextcloud Office integration recommended
  - Text files (with editor)
  - Audio playback
- Large previews are generated by the preview generator background job (may take time)

Performance tuning for Radxa (ARM64)

- PHP memory: 512M (set via env)
- Use PostgreSQL and Redis for better performance on ARM
- Use smaller Alpine-based images where available (compose uses alpine for Postgres/Redis)

Validation checklist

- After install:

  ```
  docker compose ps
  curl -I http://localhost:8081
  curl -I https://nas.soundsgoodlab.sg
  ```

- Confirm login page is shown for unauthenticated users.
- Upload files and verify previews/downloads.

Rollback & restore

- To rollback a failed update, stop containers and re-create using a previous backup of `nextcloud/html` and the PostgreSQL dump.
- Steps:

  ```
  docker compose down
  # restore files and db from backup
  docker compose up -d
  ```

Additional notes

- All services run on a single Docker bridge network named `nas_network` for internal communication.
- Environment variables are read from `.env`. Never hardcode secrets in `docker-compose.yml`.
- UID 1000 is used by Nextcloud inside the container; ensure host mount ownership matches.

Support & resources

- Nextcloud docs: <https://docs.nextcloud.com>
- Cloudflare Tunnel docs: <https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/>
- PostgreSQL docs: <https://www.postgresql.org/docs/>

License

- MIT-style for scripts and configuration provided here. Use at your own risk.
