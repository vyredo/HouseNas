
# OpenAI-Powered AI Stack Deployment (Radxa ARM64)

This document describes how to deploy the OpenAI-powered AI services alongside your existing Nextcloud without disrupting it. The stack uses profiles (core, daily, occasional), shared pgvector Postgres for AI apps, memory limits, health checks, and a single new AI network. Nextcloud remains on its original network and configuration.

Key files:

- [docker-compose.yml](docker-compose.yml)
- [.env.example](.env.example)
- [pgvector-init/00-init.sql](pgvector-init/00-init.sql:1)
- Existing Nextcloud init: [postgres-init/01-permissions.sql](postgres-init/01-permissions.sql:1)

IMPORTANT

- Nextcloud continues on port 9991 with its original database (nextcloud-db, Postgres 15).
- A new pgvector Postgres (pg17) is added for AI apps (surfsense, presenton).
- All AI services receive OPENAI_API_KEY via [.env](.env:1) (copy from [.env.example](.env.example)).

Ports

- 9991: Nextcloud (existing)
- 9992: n8n (core)
- 9993: SurfSense Backend (daily)
- 9994: SurfSense Frontend (daily)
- 9995: Open WebUI (daily)
- 9996: ComfyUI (occasional)
- 9997: Presenton (occasional)
- 9998: OpenUI (occasional)

Profiles

- core: postgres (pgvector), nextcloud, n8n
- daily: surfsense_backend, surfsense_frontend, open_webui
- occasional: comfyui, presenton, openui

1) Prepare directories

Run on the Radxa in the project root:

```bash
# Data mounts for AI services
mkdir -p ./data/postgres
mkdir -p ./data/n8n
mkdir -p ./data/surfsense/backend
mkdir -p ./data/open_webui
mkdir -p ./data/comfyui/storage
mkdir -p ./data/comfyui/config
mkdir -p ./data/presenton
mkdir -p ./data/openui

# Existing Nextcloud mounts (already present in your current setup)
mkdir -p ./nextcloud/html
mkdir -p ./nextcloud/db
mkdir -p ./nextcloud/redis
sudo mkdir -p /mnt/storage/nextcloud
sudo chown -R 1000:1000 /mnt/storage/nextcloud

# Optional: Cloudflare Tunnel credentials (if used)
mkdir -p ./secrets

# Init SQL for pgvector Postgres
mkdir -p ./pgvector-init
```

2) Configure environment variables

- Copy the template and edit secrets:

```bash
cp .env.example .env
# Edit .env and fill the values
```

Required values in [.env.example](.env.example):

- OPENAI_API_KEY for all AI services
- POSTGRES_USER, POSTGRES_PASSWORD for shared AI Postgres
- NEXTCLOUD_ADMIN_USER, NEXTCLOUD_ADMIN_PASSWORD, NEXTCLOUD_DB_PASSWORD, REDIS_PASSWORD (must match current)
- N8N_BASIC_AUTH_USER, N8N_BASIC_AUTH_PASSWORD
- NEXTAUTH_SECRET, NEXTAUTH_URL (for SurfSense)
- Optional Google OAuth

3) Initialize shared AI Postgres (pgvector)

The script [pgvector-init/00-init.sql](pgvector-init/00-init.sql:1) is auto-run on first boot to create:

- Databases: surfsense, presenton
- Extensions: vector

No ports are exposed; the DB is only reachable on the internal Docker network (ai_network).

4) Start services

Core services only:

```bash
docker compose up -d postgres nextcloud n8n
```

Core + daily services:

```bash
docker compose --profile daily up -d
```

Core + all services:

```bash
docker compose --profile daily --profile occasional up -d
```

Stop occasional services to save memory:

```bash
docker compose stop comfyui presenton openui
```

Common management:

```bash
docker compose ps
docker compose logs -f
docker compose pull && docker compose up -d
```

5) Service access URLs

- Nextcloud: <http://localhost:9991>  (existing)
- n8n: <http://localhost:9992>  (Basic Auth from .env)
- SurfSense Backend: <http://localhost:9993/healthz>
- SurfSense Frontend: <http://localhost:9994>
- Open WebUI: <http://localhost:9995/health>
- ComfyUI: <http://localhost:9996>
- Presenton: <http://localhost:9997/healthz>
- OpenUI: <http://localhost:9998/healthz>

6) Memory limits and reservations

Targets:

- Idle total: ~2–3GB
- Active (2 services): ~5–6GB

Configured per service in [docker-compose.yml](docker-compose.yml):

- nextcloud: limit 3G, reserve 512M
- nextcloud-cron: limit 512M, reserve 128M
- nextcloud-db (Postgres 15): limit 1G, reserve 256M
- redis: limit 256M, reserve 64M
- imaginary: limit 256M, reserve 64M
- postgres (pgvector/pg17): limit 512M, reserve 128M
- n8n: limit 1G, reserve 128M
- surfsense_backend: limit 1G, reserve 256M
- surfsense_frontend: limit 512M, reserve 128M
- open_webui: limit 1G, reserve 256M
- comfyui: limit 2G, reserve 256M
- presenton: limit 1G, reserve 256M
- openui: limit 512M, reserve 128M
- cloudflared (if used): limit 128M, reserve 32M

Note: Reservations are guaranteed minimums; limits are hard caps. Keeping daily/occasional services stopped when unused will keep idle memory within target.

7) Health checks

Configured with 30s interval, 10s timeout, 3 retries:

- Postgres (pgvector)
- n8n (/healthz)
- SurfSense backend (/healthz)
- SurfSense frontend (/healthz)
- Open WebUI (/health)
- ComfyUI (HTTP root)
- Presenton (/healthz)
- OpenUI (/healthz)
- nextcloud (status.php)
- redis (PING)
- nextcloud-db (pg_isready)

8) Post-deployment steps

Verify core health:

```bash
docker compose ps
curl -fsS http://localhost:9991/status.php   # Nextcloud
curl -fsS http://localhost:9992/healthz      # n8n
```

Verify daily services (if enabled):

```bash
curl -fsS http://localhost:9993/healthz      # SurfSense backend
curl -fsS http://localhost:9994/healthz || true
curl -fsS http://localhost:9995/health       # Open WebUI
```

Verify occasional services (if enabled):

```bash
curl -fsS http://localhost:9996 || true      # ComfyUI
curl -fsS http://localhost:9997/healthz      # Presenton
curl -fsS http://localhost:9998/healthz      # OpenUI
```

Install custom DALL·E nodes for ComfyUI (optional, CPU-only):

```bash
docker exec -it comfyui bash
cd /root/ComfyUI/custom_nodes
git clone https://github.com/cleanlii/comfyui-dalle-integration.git
exit
docker restart comfyui
```

n8n OpenAI usage:

- In n8n UI (<http://localhost:9992>), create credentials and workflows using OpenAI nodes.
- OPENAI_API_KEY is available as env; consider creating a global credential for reuse.

SurfSense (NextAuth) configuration:

- Ensure [NEXTAUTH_SECRET](.env.example) is a strong random string (32+ chars).
- If using Google OAuth: set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in [.env](.env:1).
- NEXTAUTH_URL should match the public URL for SurfSense frontend (default <http://localhost:9994>).

Open WebUI memory optimization:

- TRANSFORMERS_CACHE_HOME=/tmp and HF_HOME=/tmp configured to reduce persistent disk usage and memory overhead on the device.

9) Security

- No database ports are published externally.
- All services are on internal Docker networks.
- n8n is protected with Basic Auth (set in [.env](.env:1)).
- SurfSense uses NextAuth; store secrets only in [.env](.env:1).
- Never commit your real [.env](.env:1).

10) Nextcloud backward compatibility

Preserved exactly as in the existing setup:

- Ports: 9991 (unchanged)
- Volumes: ./nextcloud/html, /mnt/storage/nextcloud, ./nextcloud/db (unchanged)
- Database: nextcloud-db (Postgres 15, unchanged)
- Redis, imaginary services (unchanged)
- Cloudflare tunnel (optional) remains compatible

No changes to Nextcloud data or configs are required. The new AI services use a separate Postgres instance (pgvector pg17).

11) Troubleshooting

- Check container health:

```bash
docker compose ps
docker compose logs -f --tail=200
```

- Nextcloud not finishing setup:
  - Verify DB env in [.env](.env:1) and that nextcloud-db is healthy.
  - Ensure /mnt/storage/nextcloud is owned by UID:GID 1000:1000.

- AI Postgres init:
  - Confirm databases and vector extension exist:

```bash
docker compose exec postgres psql -U "$POSTGRES_USER" -d postgres -c "\l"
docker compose exec postgres psql -U "$POSTGRES_USER" -d surfsense -c "CREATE EXTENSION IF NOT EXISTS vector;"
docker compose exec postgres psql -U "$POSTGRES_USER" -d presenton -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

- Ports already in use:
  - Adjust host ports in [docker-compose.yml](docker-compose.yml) if 9991–9998 are occupied.

12) Update/rollback

- Update images and recreate:

```bash
docker compose pull && docker compose up -d
```

- Rollback using your existing backup routine (see [README.md](README.md:147)).

Change log
