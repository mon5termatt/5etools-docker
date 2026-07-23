FROM nginx:alpine

RUN apk add --no-cache git bash

COPY entrypoint.sh /entrypoint.sh
COPY loading/ /opt/loading/
RUN chmod +x /entrypoint.sh

# Persist clones across restarts when a volume is mounted here
VOLUME ["/data"]

ENV SRC_REPO=https://github.com/5etools-mirror-3/5etools-src.git \
    IMG_REPO=https://github.com/5etools-mirror-3/5etools-img.git \
    DATA_DIR=/data \
    AUTO_PULL_INTERVAL=3600 \
    NGINX_PORT=80

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
