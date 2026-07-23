#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
SRC_DIR="${DATA_DIR}/5etools-src"
IMG_DIR="${SRC_DIR}/img"
SRC_REPO="${SRC_REPO:-https://github.com/5etools-mirror-3/5etools-src.git}"
IMG_REPO="${IMG_REPO:-https://github.com/5etools-mirror-3/5etools-img.git}"
AUTO_PULL_INTERVAL="${AUTO_PULL_INTERVAL:-3600}"
NGINX_PORT="${NGINX_PORT:-80}"
LOADING_DIR="/opt/loading"
STATUS_FILE="/var/run/5etools-status.json"
SITE_READY_FLAG="/var/run/5etools-ready"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

write_status() {
  local ready="$1"
  local phase="$2"
  local message="$3"
  local detail="${4:-}"
  cat > "${STATUS_FILE}" <<EOF
{"ready": ${ready}, "phase": "${phase}", "message": "${message}", "detail": "${detail}"}
EOF
}

site_is_ready() {
  [[ -f "${SRC_DIR}/index.html" ]]
}

clone_or_pull() {
  local repo="$1"
  local dir="$2"
  local name="$3"

  if [[ -d "${dir}/.git" ]]; then
    log "Updating ${name}..."
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

  write_status false "cloning-src" "Downloading 5etools source…"
  clone_or_pull "${SRC_REPO}" "${SRC_DIR}" "5etools-src"

  # Source is enough to browse; flip ready so the UI can load while images continue.
  if site_is_ready; then
    touch "${SITE_READY_FLAG}"
    write_status true "cloning-img" "Source ready — downloading images…" "Images may appear as they finish."
    write_nginx_conf
    nginx -s reload 2>/dev/null || true
  else
    write_status false "cloning-img" "Downloading images (large — please wait)…"
  fi

  clone_or_pull "${IMG_REPO}" "${IMG_DIR}" "5etools-img"

  touch "${SITE_READY_FLAG}"
  write_status true "ready" "Ready"
  write_nginx_conf
  nginx -s reload 2>/dev/null || true
}

# Loading mode: missing files fall back to the loading page.
# Ready mode: serve the cloned site; still fall back to loading if index is gone mid-update.
write_nginx_conf() {
  local ready=false
  if [[ -f "${SITE_READY_FLAG}" ]] && site_is_ready; then
    ready=true
  fi

  if [[ "${ready}" == true ]]; then
    cat > /etc/nginx/conf.d/default.conf <<EOF
server {
    listen ${NGINX_PORT};
    server_name _;
    root ${SRC_DIR};
    index index.html;

    location = /status.json {
        alias ${STATUS_FILE};
        default_type application/json;
        add_header Cache-Control "no-store";
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    client_max_body_size 0;
}
EOF
  else
    mkdir -p "${SRC_DIR}"
    cat > /etc/nginx/conf.d/default.conf <<EOF
server {
    listen ${NGINX_PORT};
    server_name _;
    root ${LOADING_DIR};
    index index.html;

    location = /status.json {
        alias ${STATUS_FILE};
        default_type application/json;
        add_header Cache-Control "no-store";
    }

    # Prefer real files if a previous clone exists; otherwise show loading.
    location / {
        root ${SRC_DIR};
        try_files \$uri \$uri/ @loading;
    }

    location @loading {
        root ${LOADING_DIR};
        rewrite ^ /index.html break;
    }

    client_max_body_size 0;
}
EOF
  fi
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
      if site_is_ready; then
        write_status true "ready" "Ready — last update failed, retrying later"
      else
        write_status false "error" "Update failed — retrying next interval"
      fi
      log "Pull failed; will retry next interval"
    fi
  done
}

sync_in_background() {
  if sync_repos; then
    log "Initial sync complete"
  else
    write_status false "error" "Sync failed — check container logs"
    log "Initial sync failed"
  fi
  auto_pull_loop
}

log "Starting web UI"
mkdir -p "${DATA_DIR}" "$(dirname "${STATUS_FILE}")" "${SRC_DIR}"
rm -f "${SITE_READY_FLAG}"

if site_is_ready; then
  # Existing data: serve immediately, refresh in background
  touch "${SITE_READY_FLAG}"
  write_status true "ready" "Ready — checking for updates…"
else
  write_status false "starting" "Preparing download…"
fi

write_nginx_conf
sync_in_background &
log "Serving on port ${NGINX_PORT} (sync running in background)"
exec nginx -g "daemon off;"
