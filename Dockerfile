# cloudflare/Dockerfile
FROM cloudflare/cloudflared:latest

# 2 Add your configuration (baked into the image)
COPY config.yml /etc/cloudflared/config.yml

# 4 Set a sensible workdir
WORKDIR /etc/cloudflared

# 5 Default command (can be overridden in docker-compose.yml)
CMD ["tunnel", "run"]
