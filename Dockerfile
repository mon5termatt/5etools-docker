FROM node:24-alpine

# git for clones; nginx fronts the loading page + proxies to http-server
# python3/make/g++ cover native npm deps (e.g. sharp) when prebuilds aren't used
RUN apk add --no-cache git bash nginx python3 make g++ \
  && mkdir -p /run/nginx /var/run

COPY entrypoint.sh /entrypoint.sh
COPY loading/ /opt/loading/
RUN chmod +x /entrypoint.sh

VOLUME ["/data"]

ENV SRC_REPO=https://github.com/5etools-mirror-3/5etools-src.git \
    IMG_REPO=https://github.com/5etools-mirror-3/5etools-img.git \
    DATA_DIR=/data \
    AUTO_PULL_INTERVAL=3600 \
    PORT=80 \
    NODE_SERVE_PORT=5050 \
    BUILD_SW=true \
    BUILD_SEO=false

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
