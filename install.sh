#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${USER_NAME:-${SUDO_USER:-${USER:-}}}"
INPUT_REPO_DIR="${REPO_DIR:-}"
INPUT_VLESS_TAG="${VLESS_TAG:-}"
REPO_DIR="${INPUT_REPO_DIR:-beta}"
REPO_URL="${REPO_URL:-https://github.com/ogsvnv/beta_v2.git}"
SERVER_HOST="${SERVER_HOST:-}"
MODE="${MODE:-}"
INPUT_XRAY_PORT="${XRAY_PORT:-}"
XRAY_PORT="${INPUT_XRAY_PORT:-8443}"
XUI_PORT="${XUI_PORT:-2053}"
VLESS_UUID="${VLESS_UUID:-}"
VLESS_TAG="${INPUT_VLESS_TAG:-$REPO_DIR}"
REALITY_SNI="${REALITY_SNI:-www.dropbox.com}"
REALITY_DEST="${REALITY_DEST:-${REALITY_SNI}:443}"
REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-chrome}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"
XHTTP_PATH="${XHTTP_PATH:-/xhttp}"
GRPC_SERVICE_NAME="${GRPC_SERVICE_NAME:-beta}"
CDN_WS_PATH="${CDN_WS_PATH:-/ray}"
CDN_PORT="${CDN_PORT:-443}"
LOGLEVEL="${LOGLEVEL:-info}"
TELEGRAM_CHAT_ADMIN="${TELEGRAM_CHAT_ADMIN:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
BETA_PROJECT_DIR_HOST="${BETA_PROJECT_DIR_HOST:-/beta}"
REALITY_ALERT_COOLDOWN_SECONDS="${REALITY_ALERT_COOLDOWN_SECONDS:-300}"
REALITY_ALERT_STARTUP_TEST_ENABLED="${REALITY_ALERT_STARTUP_TEST_ENABLED:-1}"

usage() {
  cat <<'EOF'
Usage:
  install.sh [host] [mode]
  install.sh --host example.com --grpc
  install.sh --host example.com --grpc-tls
  install.sh --host example.com --grpc --project-name beta

Modes:
  --tcp, --reality      MODE=1 VLESS TCP/RAW REALITY Vision
  --xhttp              MODE=2 VLESS XHTTP REALITY
  --grpc               MODE=3 VLESS gRPC REALITY
  --cdn, --ws          MODE=4 VLESS WebSocket CDN
  --grpc-tls, --caddy  MODE=5 VLESS gRPC TLS Caddy
EOF
}

prompt_value() {
  local prompt="$1"
  local default_value="${2:-}"
  local answer=""

  if [[ -r /dev/tty ]]; then
    if [[ -n "$default_value" ]]; then
      read -r -p "$prompt [$default_value]: " answer < /dev/tty
      printf '%s\n' "${answer:-$default_value}"
    else
      read -r -p "$prompt: " answer < /dev/tty
      printf '%s\n' "$answer"
    fi
    return
  fi

  if [[ -n "$default_value" ]]; then
    printf '%s\n' "$default_value"
    return
  fi

  echo "$prompt is required; pass it as an argument when running without a TTY" >&2
  exit 1
}

mode_from_value() {
  case "${1,,}" in
    1 | tcp | raw | vision | reality | --tcp | --raw | --vision | --reality)
      MODE="1"
      XRAY_MODE="tcp"
      ;;
    2 | xhttp | --xhttp)
      MODE="2"
      XRAY_MODE="xhttp"
      ;;
    3 | grpc | --grpc)
      MODE="3"
      XRAY_MODE="grpc"
      ;;
    4 | cdn | ws | cdn-ws | websocket | --cdn | --ws | --cdn-ws | --websocket)
      MODE="4"
      XRAY_MODE="cdn-ws"
      ;;
    5 | grpc-tls | tls-grpc | caddy | caddy-grpc | --grpc-tls | --tls-grpc | --caddy | --caddy-grpc)
      MODE="5"
      XRAY_MODE="grpc-tls"
      ;;
    *)
      echo "Unknown mode: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --host)
        SERVER_HOST="${2:-}"
        shift 2
        ;;
      --mode)
        mode_from_value "${2:-}"
        shift 2
        ;;
      --xray-port)
        XRAY_PORT="${2:-}"
        INPUT_XRAY_PORT="$XRAY_PORT"
        shift 2
        ;;
      --xui-port)
        XUI_PORT="${2:-}"
        shift 2
        ;;
      --repo-dir | --project-name)
        REPO_DIR="${2:-}"
        if [[ -z "$INPUT_VLESS_TAG" ]]; then
          VLESS_TAG="$REPO_DIR"
        fi
        shift 2
        ;;
      --tag | --vless-tag)
        VLESS_TAG="${2:-}"
        INPUT_VLESS_TAG="$VLESS_TAG"
        shift 2
        ;;
      --tcp | --raw | --vision | --reality | --xhttp | --grpc | --cdn | --ws | --cdn-ws | --websocket | --grpc-tls | --tls-grpc | --caddy | --caddy-grpc)
        mode_from_value "$1"
        shift
        ;;
      -*)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
      *)
        if [[ -z "$SERVER_HOST" ]]; then
          SERVER_HOST="$1"
        elif [[ -z "$MODE" ]]; then
          mode_from_value "$1"
        else
          echo "Unexpected argument: $1" >&2
          usage >&2
          exit 1
        fi
        shift
        ;;
    esac
  done
}

ask_project_name() {
  if [[ -n "$INPUT_REPO_DIR" || -n "$INPUT_VLESS_TAG" ]]; then
    return
  fi

  PROJECT_NAME="$(prompt_value "Project name / VLESS tag" "beta")"
  REPO_DIR="$PROJECT_NAME"
  VLESS_TAG="$PROJECT_NAME"
}

select_mode() {
  if [[ -n "$MODE" ]]; then
    mode_from_value "$MODE"
    return
  fi

  cat <<'MENU'
Select install mode:
  1. VLESS + TCP/RAW + REALITY + Vision
  2. VLESS + XHTTP + REALITY
  3. VLESS + gRPC + REALITY
  4. VLESS + WebSocket + CDN
  5. VLESS + gRPC + TLS + Caddy
MENU
  MODE="$(prompt_value "Mode" "1")"
  mode_from_value "$MODE"
}

ensure_defaults() {
  if [[ "$XRAY_MODE" == "cdn-ws" && -z "$INPUT_XRAY_PORT" ]]; then
    XRAY_PORT="80"
  elif [[ "$XRAY_MODE" == "grpc-tls" && -z "$INPUT_XRAY_PORT" ]]; then
    XRAY_PORT="443"
  fi

  if [[ "$XRAY_MODE" == "grpc-tls" && "$GRPC_SERVICE_NAME" == "beta" ]]; then
    GRPC_SERVICE_NAME="beta"
  fi

  if [[ -z "$SERVER_HOST" ]]; then
    SERVER_HOST="$(prompt_value "Server host or IP/domain")"
  fi

  if [[ -z "$SERVER_HOST" ]]; then
    echo "SERVER_HOST is required" >&2
    exit 1
  fi
}

current_session_has_group() {
  local group_name="$1"
  id -nG 2>/dev/null | tr ' ' '\n' | grep -qx "$group_name"
}

docker_is_installed() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

has_systemd() {
  [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

start_service_if_possible() {
  local service_name="$1"

  if has_systemd; then
    sudo systemctl enable "$service_name" || true
    sudo systemctl start "$service_name" || true
    return
  fi

  if command -v service >/dev/null 2>&1; then
    sudo service "$service_name" start || true
    return
  fi

  echo "No supported service manager found, skipping $service_name service start."
}

can_manage_iptables() {
  command -v iptables >/dev/null 2>&1 && sudo iptables -w -L -n >/dev/null 2>&1
}

require_docker_relogin_if_needed() {
  sudo usermod -aG docker "$USER_NAME"
  if id ogsvnv >/dev/null 2>&1; then
    sudo usermod -aG docker ogsvnv
  fi

  if [[ "$(id -u)" -eq 0 ]] || current_session_has_group docker; then
    return
  fi

  cat <<EOF

Docker installed and user '$USER_NAME' was added to the docker group.
Log out, log back in, then run the installer again so this shell receives the new group.

Example:
  wget -O - https://raw.githubusercontent.com/ogsvnv/beta_v2/main/install.sh | bash

EOF
  exit 0
}

install_system() {
  echo "=============================="
  echo "[1/9] Updating apt index"
  echo "=============================="
  sudo apt update

  echo "=============================="
  echo "[2/9] Installing base packages"
  echo "=============================="
  sudo apt install -y ca-certificates curl gnupg git ufw vnstat

  echo "=============================="
  echo "[3/9] Installing Docker"
  echo "=============================="
  if docker_is_installed; then
    echo "Docker is already installed, skipping Docker package installation."
  else
    sudo install -m 0755 -d /etc/apt/keyrings

    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
      echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi

    sudo apt update
    sudo apt install -y \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-buildx-plugin \
      docker-compose-plugin
  fi

  start_service_if_possible docker
  require_docker_relogin_if_needed

  echo "=============================="
  echo "[4/9] Starting vnStat"
  echo "=============================="
  start_service_if_possible vnstat
  if has_systemd; then
    sudo systemctl status vnstat --no-pager || true
  fi
  vnstat || true
}

configure_firewall() {
  echo "=============================="
  echo "[5/9] Configuring firewall"
  echo "=============================="
  if ! command -v ufw >/dev/null 2>&1; then
    echo "UFW is not installed, skipping firewall configuration."
    return
  fi

  if ! can_manage_iptables; then
    echo "WARN: iptables is not available to this environment, skipping UFW configuration."
    echo "WARN: This is common inside containers. On a VPS, run the installer with sudo-capable user privileges."
    echo "WARN: Open the required ports in your VPS firewall/security group instead."
    return
  fi

  sudo ufw allow 22/tcp || echo "WARN: failed to add UFW rule for 22/tcp."
  if [[ "$XRAY_MODE" == "grpc-tls" ]]; then
    sudo ufw allow 80/tcp || echo "WARN: failed to add UFW rule for 80/tcp."
    sudo ufw allow 443/tcp || echo "WARN: failed to add UFW rule for 443/tcp."
  else
    sudo ufw allow "$XRAY_PORT/tcp" || echo "WARN: failed to add UFW rule for $XRAY_PORT/tcp."
  fi
  sudo ufw allow "$XUI_PORT/tcp" || echo "WARN: failed to add UFW rule for $XUI_PORT/tcp."

  if ! sudo ufw --force enable; then
    echo "WARN: UFW could not be enabled. This often happens in containers without iptables/sysctl permissions."
    echo "WARN: Open the required ports in your VPS firewall/security group instead."
    return
  fi

  sudo ufw status verbose || true
}

prepare_repo() {
  if [[ -z "$USER_NAME" ]]; then
    echo "USER_NAME is required" >&2
    exit 1
  fi

  USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
  if [[ -z "$USER_HOME" ]]; then
    echo "Cannot detect home directory for user: $USER_NAME" >&2
    exit 1
  fi

  APP_DIR="$USER_HOME/$REPO_DIR"

  echo "=============================="
  echo "[6/9] Cloning/updating project"
  echo "=============================="
  if [[ -d "$APP_DIR/.git" ]]; then
    sudo -u "$USER_NAME" git -C "$APP_DIR" pull --ff-only
  elif [[ -e "$APP_DIR" ]]; then
    echo "$APP_DIR exists but is not a git repository" >&2
    exit 1
  else
    sudo -u "$USER_NAME" git clone "$REPO_URL" "$APP_DIR"
  fi
}

generate_uuid_and_keys() {
  if [[ "$VLESS_UUID" == "00000000-0000-0000-0000-000000000000" ]]; then
    VLESS_UUID=""
  fi

  if [[ -z "$VLESS_UUID" || "${FORCE_NEW_UUID:-0}" == "1" ]]; then
    if command -v uuidgen >/dev/null 2>&1; then
      VLESS_UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    else
      VLESS_UUID="$(cat /proc/sys/kernel/random/uuid)"
    fi
  fi

  if [[ "$XRAY_MODE" != "cdn-ws" && "$XRAY_MODE" != "grpc-tls" ]]; then
    if [[ "$REALITY_SHORT_ID" == "a1b2c3d4" || ${#REALITY_SHORT_ID} -lt 16 ]]; then
      REALITY_SHORT_ID=""
    fi

    if [[ -z "$REALITY_SHORT_ID" || "${FORCE_NEW_REALITY:-0}" == "1" ]]; then
      REALITY_SHORT_ID="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
    fi

    if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" || "${FORCE_NEW_REALITY:-0}" == "1" ]]; then
      REALITY_KEYS="$(docker run --rm ghcr.io/xtls/xray-core:latest x25519)"
      REALITY_PRIVATE_KEY="$(printf '%s\n' "$REALITY_KEYS" | awk -F': ' '/PrivateKey|Private key/ {print $2; exit}')"
      REALITY_PUBLIC_KEY="$(printf '%s\n' "$REALITY_KEYS" | awk -F': ' '/PublicKey|Public key/ {print $2; exit}')"

      if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
        echo "Failed to parse REALITY keys from xray x25519 output" >&2
        exit 1
      fi
    fi
  fi
}

write_xray_config() {
  local config_file="$APP_DIR/config/xray.json"
  local nginx_file="$APP_DIR/config/nginx.conf"
  local caddy_file="$APP_DIR/config/Caddyfile"
  mkdir -p "$APP_DIR/config"

  if [[ "$XRAY_MODE" == "cdn-ws" ]]; then
    cat > "$config_file" <<EOF
{
  "log": {
    "loglevel": "$LOGLEVEL"
  },
  "inbounds": [
    {
      "tag": "vless-cdn-ws",
      "port": 10000,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$VLESS_UUID",
            "email": "default@xray.local"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "$CDN_WS_PATH"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "blocked",
      "protocol": "blackhole"
    }
  ]
}
EOF

    cat > "$nginx_file" <<EOF
worker_processes auto;

events {
  worker_connections 1024;
}

http {
  server {
    listen 8443;

    location $CDN_WS_PATH {
      proxy_pass http://xray:10000;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host;
      proxy_read_timeout 1h;
      proxy_send_timeout 1h;
    }

    location / {
      return 404;
    }
  }
}
EOF
  elif [[ "$XRAY_MODE" == "grpc-tls" ]]; then
    cat > "$config_file" <<EOF
{
  "log": {
    "loglevel": "$LOGLEVEL"
  },
  "inbounds": [
    {
      "tag": "vless-grpc-tls",
      "port": 10000,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$VLESS_UUID",
            "email": "default@xray.local"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": {
          "serviceName": "$GRPC_SERVICE_NAME"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "blocked",
      "protocol": "blackhole"
    }
  ]
}
EOF

    cat > "$caddy_file" <<EOF
$SERVER_HOST {
  encode zstd gzip

  reverse_proxy /$GRPC_SERVICE_NAME/Tun* h2c://xray:10000

  respond "OK" 200
}
EOF
  else
    local client_flow_line=""
    local transport_settings=""

    case "$XRAY_MODE" in
      tcp)
        client_flow_line='            "flow": "xtls-rprx-vision",'
        transport_settings='        "network": "tcp",
        "security": "reality",'
        ;;
      xhttp)
        transport_settings='        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "'"$XHTTP_PATH"'"
        },'
        ;;
      grpc)
        transport_settings='        "network": "grpc",
        "security": "reality",
        "grpcSettings": {
          "serviceName": "'"$GRPC_SERVICE_NAME"'"
        },'
        ;;
    esac

    cat > "$config_file" <<EOF
{
  "log": {
    "loglevel": "$LOGLEVEL"
  },
  "inbounds": [
    {
      "tag": "vless-in",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$VLESS_UUID",
$client_flow_line
            "email": "default@xray.local"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
$transport_settings
        "realitySettings": {
          "show": false,
          "target": "$REALITY_DEST",
          "xver": 0,
          "serverNames": [
            "$REALITY_SNI"
          ],
          "privateKey": "$REALITY_PRIVATE_KEY",
          "shortIds": [
            "$REALITY_SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "blocked",
      "protocol": "blackhole"
    }
  ]
}
EOF

    cat > "$nginx_file" <<EOF
worker_processes auto;

events {
  worker_connections 1024;
}

stream {
  upstream xray_vless {
    server xray:443;
  }

  server {
    listen 8443;
    proxy_pass xray_vless;
    proxy_connect_timeout 10s;
    proxy_timeout 1h;
  }
}
EOF
  fi

  chmod 644 "$config_file"
  [[ -f "$nginx_file" ]] && chmod 644 "$nginx_file"
  [[ -f "$caddy_file" ]] && chmod 644 "$caddy_file"
}

write_compose() {
  local compose_file="$APP_DIR/docker-compose.yml"
  local template_file=""

  case "$MODE" in
    1) template_file="$APP_DIR/compose/docker-compose.mode1-tcp-reality.yml" ;;
    2) template_file="$APP_DIR/compose/docker-compose.mode2-xhttp-reality.yml" ;;
    3) template_file="$APP_DIR/compose/docker-compose.mode3-grpc-reality.yml" ;;
    4) template_file="$APP_DIR/compose/docker-compose.mode4-cdn-ws.yml" ;;
    5) template_file="$APP_DIR/compose/docker-compose.mode5-grpc-tls-caddy.yml" ;;
  esac

  cp "$template_file" "$compose_file"
  chmod 644 "$compose_file"
}

write_env() {
  cat > "$APP_DIR/.env" <<EOF
SERVER_HOST=$SERVER_HOST
MODE=$MODE
XRAY_MODE=$XRAY_MODE
XRAY_PORT=$XRAY_PORT
XUI_PORT=$XUI_PORT
VLESS_UUID=$VLESS_UUID
VLESS_TAG=$VLESS_TAG
REALITY_SNI=$REALITY_SNI
REALITY_DEST=$REALITY_DEST
REALITY_FINGERPRINT=$REALITY_FINGERPRINT
REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID
XHTTP_PATH=$XHTTP_PATH
GRPC_SERVICE_NAME=$GRPC_SERVICE_NAME
CDN_WS_PATH=$CDN_WS_PATH
CDN_PORT=$CDN_PORT
LOGLEVEL=$LOGLEVEL
TELEGRAM_CHAT_ADMIN=$TELEGRAM_CHAT_ADMIN
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
BETA_PROJECT_DIR_HOST=$BETA_PROJECT_DIR_HOST
REALITY_ALERT_COOLDOWN_SECONDS=$REALITY_ALERT_COOLDOWN_SECONDS
REALITY_ALERT_STARTUP_TEST_ENABLED=$REALITY_ALERT_STARTUP_TEST_ENABLED
EOF
  chmod 600 "$APP_DIR/.env"
}

build_link() {
  case "$XRAY_MODE" in
    tcp)
      LINK="vless://${VLESS_UUID}@${SERVER_HOST}:${XRAY_PORT}?flow=xtls-rprx-vision&type=tcp&headerType=none&security=reality&fp=${REALITY_FINGERPRINT}&sni=${REALITY_SNI}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}#${VLESS_TAG}"
      ;;
    xhttp)
      local encoded_xhttp_path="${XHTTP_PATH//\//%2F}"
      LINK="vless://${VLESS_UUID}@${SERVER_HOST}:${XRAY_PORT}?type=xhttp&path=${encoded_xhttp_path}&security=reality&fp=${REALITY_FINGERPRINT}&sni=${REALITY_SNI}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}#${VLESS_TAG}"
      ;;
    grpc)
      LINK="vless://${VLESS_UUID}@${SERVER_HOST}:${XRAY_PORT}?type=grpc&serviceName=${GRPC_SERVICE_NAME}&mode=gun&security=reality&fp=${REALITY_FINGERPRINT}&sni=${REALITY_SNI}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}#${VLESS_TAG}"
      ;;
    cdn-ws)
      local encoded_cdn_ws_path="${CDN_WS_PATH//\//%2F}"
      LINK="vless://${VLESS_UUID}@${SERVER_HOST}:${CDN_PORT}?type=ws&host=${SERVER_HOST}&path=${encoded_cdn_ws_path}&security=tls&sni=${SERVER_HOST}#${VLESS_TAG}"
      ;;
    grpc-tls)
      LINK="vless://${VLESS_UUID}@${SERVER_HOST}:443?type=grpc&serviceName=${GRPC_SERVICE_NAME}&mode=gun&security=tls&sni=${SERVER_HOST}#${VLESS_TAG}"
      ;;
  esac
}

configure_project() {
  echo "=============================="
  echo "[7/9] Creating config"
  echo "=============================="
  generate_uuid_and_keys
  write_xray_config
  write_compose
  write_env
  sudo chown -R "$USER_NAME:$USER_NAME" "$APP_DIR"
}

start_compose() {
  echo "=============================="
  echo "[8/9] Starting Docker Compose"
  echo "=============================="
  cd "$APP_DIR"
  docker compose up -d
}

print_link() {
  echo "=============================="
  echo "[9/9] VLESS link"
  echo "=============================="
  build_link
  echo "VLESS link:"
  echo "$LINK"
  echo
  echo "3x-ui:"
  echo "http://${SERVER_HOST}:${XUI_PORT}/panel"
}

main() {
  parse_args "$@"
  install_system
  ask_project_name
  select_mode
  ensure_defaults
  configure_firewall
  prepare_repo
  configure_project
  start_compose
  print_link
}

main "$@"
