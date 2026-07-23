#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
SRC_DIR="${DATA_DIR}/5etools-src"
IMG_DIR="${SRC_DIR}/img"
SRC_REPO="${SRC_REPO:-https://github.com/5etools-mirror-3/5etools-src.git}"
IMG_REPO="${IMG_REPO:-https://github.com/5etools-mirror-3/5etools-img.git}"
AUTO_PULL_INTERVAL="${AUTO_PULL_INTERVAL:-3600}"
NGINX_PORT="${NGINX_PORT:-80}"
NGINX_ROOT="/usr/share/nginx/html"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

clone_or_pull() {
  local repo="$1"
  local dir="$2"
  local name="$3"

  if [[ -d "${dir}/.git" ]]; then
    log "Updating ${name}..."
    # Shallow update to latest default branch tip
    git -C "${dir}" remote set-url origin "${repo}"
    git -C "${dir}" fetch --depth 1 origin HEAD
    git -C "${dir}" reset --hard FETCH_HEAD
  else
    log "Cloning ${name} (this can take a while for images)..."
    rm -rf "${dir}"
    mkdir -p "$(dirname "${dir}")"
    git clone --depth 1 "${repo}" "${dir}"
  fi
}

sync_repos() {
  mkdir -p "${DATA_DIR}"
  clone_or_pull "${SRC_REPO}" "${SRC_DIR}" "5etools-src"
  clone_or_pull "${IMG_REPO}" "${IMG_DIR}" "5etools-img"
}

link_webroot() {
  rm -rf "${NGINX_ROOT}"
  ln -sfn "${SRC_DIR}" "${NGINX_ROOT}"
}

write_nginx_conf() {
  cat > /etc/nginx/conf.d/default.conf <<EOF
server {
    listen ${NGINX_PORT};
    server_name _;
    root ${NGINX_ROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Large image payloads
    client_max_body_size 0;
}
EOF
}

auto_pull_loop() {
  if [[ "${AUTO_PULL_INTERVAL}" -le 0 ]]; then
    log "Auto-pull disabled (AUTO_PULL_INTERVAL=${AUTO_PULL_INTERVAL})"
    return 0
  fi

  log "Auto-pull every ${AUTO_PULL_INTERVAL}s"
  while true; do
    sleep "${AUTO_PULL_INTERVAL}"
    log "Scheduled pull..."
    if sync_repos; then
      log "Pull complete"
    else
      log "Pull failed; will retry next interval"
    fi
  done
}

log "Starting 5etools sync + serve"
sync_repos
link_webroot
write_nginx_conf

auto_pull_loop &
log "Serving ${SRC_DIR} on port ${NGINX_PORT}"
exec nginx -g "daemon off;"
