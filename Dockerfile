FROM nextcloud:latest

RUN set -ex; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
  ffmpeg \
  ghostscript \
  imagemagick \
  ; \
  rm -rf /var/lib/apt/lists/*; \
  sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' /etc/ImageMagick-7/policy.xml
