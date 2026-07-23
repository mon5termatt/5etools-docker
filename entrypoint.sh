#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
SRC_DIR="${DATA_DIR}/5etools-src"
IMG_DIR="${SRC_DIR}/img"
SRC_REPO="${SRC_REPO:-https://github.com/5etools-mirror-3/5etools-src.git}"
IMG_REPO="${IMG_REPO:-https://github.com/5etools-mirror-3/5etools-img.git}"
AUTO_PULL_INTERVAL="${AUTO_PULL_INTERVAL:-3600}"
PORT="${PORT:-80}"
NODE_SERVE_PORT="${NODE_SERVE_PORT:-5050}"
BUILD_SW="${BUILD_SW:-true}"
BUILD_SEO="${BUILD_SEO:-false}"
LOADING_DIR="/opt/loading"
STATUS_FILE="/var/run/5etools-status.json"
SITE_READY_FLAG="/var/run/5etools-ready"
HTTP_PID_FILE="/var/run/5etools-http.pid"
NGINX_CONF="/etc/nginx/http.d/default.conf"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" >>/proc/1/fd/1
}

write_status() {
  local ready="$1"
  local phase="$2"
  local message="$3"
  local detail="${4:-}"
  # Escape quotes in message/detail for JSON
  message="${message//\"/\\\"}"
  detail="${detail//\"/\\\"}"
  cat > "${STATUS_FILE}" <<EOF
{"ready": ${ready}, "phase": "${phase}", "message": "${message}", "detail": "${detail}"}
EOF
}

site_files_present() {
  [[ -f "${SRC_DIR}/index.html" && -f "${SRC_DIR}/package.json" ]]
}

deps_installed() {
  [[ -d "${SRC_DIR}/node_modules/http-server" ]]
}

http_server_up() {
  node -e "fetch('http://127.0.0.1:${NODE_SERVE_PORT}/').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
}

clone_or_pull() {
  local repo="$1"
  local dir="$2"
  local name="$3"

  if [[ -d "${dir}/.git" ]]; then
    log "Updating ${name}..."
    git -C "${dir}" remote set-url origin "${repo}"
    git -C "${dir}" fetch --depth 1 origin HEAD >>/proc/1/fd/1 2>>/proc/1/fd/2
    git -C "${dir}" reset --hard FETCH_HEAD >>/proc/1/fd/1 2>>/proc/1/fd/2
  else
    log "Cloning ${name}..."
    rm -rf "${dir}"
    mkdir -p "$(dirname "${dir}")"
    git clone --depth 1 --progress "${repo}" "${dir}" >>/proc/1/fd/1 2>>/proc/1/fd/2
  fi
}

install_and_build() {
  cd "${SRC_DIR}"

  write_status false "npm-install" "Installing Node dependencies (npm i)…"
  log "Running npm i…"
  npm i --loglevel info >>/proc/1/fd/1 2>>/proc/1/fd/2

  if [[ "${BUILD_SW}" =~ ^(true|TRUE|1|yes|YES)$ ]]; then
    write_status false "build-sw" "Building service worker…"
    log "Running npm run build:sw:prod…"
    npm run build:sw:prod >>/proc/1/fd/1 2>>/proc/1/fd/2
  fi

  if [[ "${BUILD_SEO}" =~ ^(true|TRUE|1|yes|YES)$ ]]; then
    write_status false "build-seo" "Building SEO pages (this can take a while)…"
    log "Running npm run build:seo…"
    npm run build:seo >>/proc/1/fd/1 2>>/proc/1/fd/2
  fi
}

stop_http_server() {
  if [[ -f "${HTTP_PID_FILE}" ]]; then
    local pid
    pid="$(cat "${HTTP_PID_FILE}" || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      log "Stopping http-server (pid ${pid})"
      # Kill the whole process group (npm + http-server)
      kill -- "-${pid}" 2>/dev/null || kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
    fi
    rm -f "${HTTP_PID_FILE}"
  fi
  pkill -f "http-server.*${NODE_SERVE_PORT}" 2>/dev/null || true
}

start_http_server() {
  stop_http_server
  cd "${SRC_DIR}"
  log "Starting npm run serve:dev (port ${NODE_SERVE_PORT})"
  # https://wiki.tercept.net/en/5eTools/InstallGuide — Host with Node.js
  # Stream logs to PID 1 fds so they show up in `docker compose logs`
  setsid npm run serve:dev >>/proc/1/fd/1 2>>/proc/1/fd/2 &
  echo $! > "${HTTP_PID_FILE}"

  local i
  for i in $(seq 1 60); do
    if http_server_up; then
      log "http-server is up"
      return 0
    fi
    sleep 0.5
  done
  log "WARNING: http-server did not become ready in time"
  return 1
}

mark_ready_and_proxy() {
  touch "${SITE_READY_FLAG}"
  write_nginx_conf
  nginx -s reload 2>/dev/null || true
}

sync_repos() {
  mkdir -p "${DATA_DIR}"

  write_status false "cloning-src" "Downloading 5etools source…"
  clone_or_pull "${SRC_REPO}" "${SRC_DIR}" "5etools-src"

  install_and_build
  start_http_server
  write_status true "cloning-img" "Site ready — downloading images…" "You can browse now; images may appear as they finish."
  mark_ready_and_proxy

  write_status true "cloning-img" "Downloading images (large — please wait)…"
  clone_or_pull "${IMG_REPO}" "${IMG_DIR}" "5etools-img"

  write_status true "ready" "Ready"
  mark_ready_and_proxy
}

write_nginx_conf() {
  local ready=false
  if [[ -f "${SITE_READY_FLAG}" ]] && http_server_up; then
    ready=true
  fi

  mkdir -p "$(dirname "${NGINX_CONF}")"

  if [[ "${ready}" == true ]]; then
    cat > "${NGINX_CONF}" <<EOF
server {
    listen ${PORT} default_server;
    server_name _;

    location = /status.json {
        alias ${STATUS_FILE};
        default_type application/json;
        add_header Cache-Control "no-store";
    }

    location / {
        proxy_pass http://127.0.0.1:${NODE_SERVE_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
    }

    client_max_body_size 0;
}
EOF
  else
    mkdir -p "${SRC_DIR}"
    cat > "${NGINX_CONF}" <<EOF
server {
    listen ${PORT} default_server;
    server_name _;
    root ${LOADING_DIR};
    index index.html;

    location = /status.json {
        alias ${STATUS_FILE};
        default_type application/json;
        add_header Cache-Control "no-store";
    }

    # If Node is already up (restart), proxy; otherwise show loading for missing files.
    location / {
        error_page 502 503 504 = @loading;
        proxy_intercept_errors on;
        proxy_pass http://127.0.0.1:${NODE_SERVE_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_connect_timeout 1s;
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
    log "Scheduled pull…"
    if sync_repos; then
      log "Pull complete"
    else
      if http_server_up; then
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

# --- boot ---
log "Starting 5etools (Node serve:dev per install guide)"
mkdir -p "${DATA_DIR}" "$(dirname "${STATUS_FILE}")" "${SRC_DIR}" /run/nginx
rm -f "${SITE_READY_FLAG}"

# Ensure Alpine nginx has a main config include for http.d
if [[ ! -f /etc/nginx/nginx.conf ]]; then
  log "ERROR: nginx is not installed correctly"
  exit 1
fi

# Remove stock default that may conflict
rm -f /etc/nginx/http.d/default.conf

if site_files_present && deps_installed; then
  write_status true "starting" "Starting site from existing files…"
  if start_http_server; then
    touch "${SITE_READY_FLAG}"
    write_status true "ready" "Ready — checking for updates…"
  else
    write_status false "starting" "Preparing download…"
  fi
else
  write_status false "starting" "Preparing download…"
fi

write_nginx_conf
sync_in_background &

log "Front door on :${PORT} → Node http-server :${NODE_SERVE_PORT}"
exec nginx -g "daemon off;"
