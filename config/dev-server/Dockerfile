# Nextcloud's image ships without ffmpeg, so it can't make video thumbnails.
FROM docker.io/library/nextcloud:34.0.5-apache
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/*
