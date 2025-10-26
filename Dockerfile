FROM nextcloud:latest

RUN set -ex; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
  ffmpeg \
  ghostscript \
  libmagickcore-7.q16-10-extra \
  ; \
  rm -rf /var/lib/apt/lists/*
