FROM nextcloud:latest

RUN set -ex; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
  ffmpeg \
  ghostscript \
  imagemagick \
  ; \
  rm -rf /var/lib/apt/lists/*
