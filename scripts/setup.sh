#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
CONFIG_FILE="$ROOT_DIR/config/xray.json"
NGINX_CONFIG_FILE="$ROOT_DIR/config/nginx.conf"

INPUT_SERVER_HOST="${1:-${SERVER_HOST:-}}"
INPUT_MODE="${2:-${MODE:-${XRAY_MODE:-}}}"
INPUT_XRAY_PORT="${XRAY_PORT:-}"
INPUT_VLESS_UUID="${VLESS_UUID:-}"
INPUT_VLESS_TAG="${VLESS_TAG:-}"
INPUT_REALITY_SNI="${REALITY_SNI:-}"
INPUT_REALITY_DEST="${REALITY_DEST:-}"
INPUT_REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-}"
INPUT_REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
INPUT_REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
INPUT_REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"
INPUT_XHTTP_PATH="${XHTTP_PATH:-}"
INPUT_GRPC_SERVICE_NAME="${GRPC_SERVICE_NAME:-}"
INPUT_CDN_WS_PATH="${CDN_WS_PATH:-}"
INPUT_CDN_PORT="${CDN_PORT:-}"
INPUT_LOGLEVEL="${LOGLEVEL:-}"
INPUT_TELEGRAM_CHAT_ADMIN="${TELEGRAM_CHAT_ADMIN:-}"
INPUT_TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
INPUT_GAMMA_PROJECT_DIR_HOST="${GAMMA_PROJECT_DIR_HOST:-}"
INPUT_REALITY_ALERT_COOLDOWN_SECONDS="${REALITY_ALERT_COOLDOWN_SECONDS:-}"
INPUT_REALITY_ALERT_STARTUP_TEST_ENABLED="${REALITY_ALERT_STARTUP_TEST_ENABLED:-}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

SERVER_HOST="${INPUT_SERVER_HOST:-${SERVER_HOST:-}}"
MODE="${INPUT_MODE:-${MODE:-${XRAY_MODE:-1}}}"
XRAY_PORT="${INPUT_XRAY_PORT:-${XRAY_PORT:-8443}}"
VLESS_UUID="${INPUT_VLESS_UUID:-${VLESS_UUID:-}}"
VLESS_TAG="${INPUT_VLESS_TAG:-${VLESS_TAG:-home-xray}}"
REALITY_SNI="${INPUT_REALITY_SNI:-${REALITY_SNI:-www.dropbox.com}}"
REALITY_DEST="${INPUT_REALITY_DEST:-${REALITY_DEST:-${REALITY_SNI}:443}}"
REALITY_FINGERPRINT="${INPUT_REALITY_FINGERPRINT:-${REALITY_FINGERPRINT:-chrome}}"
REALITY_PRIVATE_KEY="${INPUT_REALITY_PRIVATE_KEY:-${REALITY_PRIVATE_KEY:-}}"
REALITY_PUBLIC_KEY="${INPUT_REALITY_PUBLIC_KEY:-${REALITY_PUBLIC_KEY:-}}"
REALITY_SHORT_ID="${INPUT_REALITY_SHORT_ID:-${REALITY_SHORT_ID:-}}"
XHTTP_PATH="${INPUT_XHTTP_PATH:-${XHTTP_PATH:-/xhttp}}"
GRPC_SERVICE_NAME="${INPUT_GRPC_SERVICE_NAME:-${GRPC_SERVICE_NAME:-home-xray}}"
CDN_WS_PATH="${INPUT_CDN_WS_PATH:-${CDN_WS_PATH:-/ray}}"
CDN_PORT="${INPUT_CDN_PORT:-${CDN_PORT:-443}}"
LOGLEVEL="${INPUT_LOGLEVEL:-${LOGLEVEL:-info}}"
TELEGRAM_CHAT_ADMIN="${INPUT_TELEGRAM_CHAT_ADMIN:-${TELEGRAM_CHAT_ADMIN:-}}"
TELEGRAM_BOT_TOKEN="${INPUT_TELEGRAM_BOT_TOKEN:-${TELEGRAM_BOT_TOKEN:-}}"
GAMMA_PROJECT_DIR_HOST="${INPUT_GAMMA_PROJECT_DIR_HOST:-${GAMMA_PROJECT_DIR_HOST:-/gamma}}"
REALITY_ALERT_COOLDOWN_SECONDS="${INPUT_REALITY_ALERT_COOLDOWN_SECONDS:-${REALITY_ALERT_COOLDOWN_SECONDS:-300}}"
REALITY_ALERT_STARTUP_TEST_ENABLED="${INPUT_REALITY_ALERT_STARTUP_TEST_ENABLED:-${REALITY_ALERT_STARTUP_TEST_ENABLED:-1}}"

case "$MODE" in
  1 | tcp | raw | vision)
    MODE="1"
    XRAY_MODE="tcp"
    ;;
  2 | xhttp)
    MODE="2"
    XRAY_MODE="xhttp"
    ;;
  3 | grpc)
    MODE="3"
    XRAY_MODE="grpc"
    ;;
  4 | cdn | ws | cdn-ws | websocket)
    MODE="4"
    XRAY_MODE="cdn-ws"
    if [[ -z "$INPUT_XRAY_PORT" ]]; then
      XRAY_PORT="80"
    fi
    ;;
  *)
    echo "Unknown MODE: $MODE" >&2
    echo "Use one of: 1, 2, 3, 4" >&2
    exit 1
    ;;
esac

if [[ -z "$SERVER_HOST" ]]; then
  read -r -p "Server host or IP: " SERVER_HOST
fi

if [[ -z "$SERVER_HOST" ]]; then
  echo "Server host is required" >&2
  exit 1
fi

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

if [[ "$XRAY_MODE" != "cdn-ws" ]]; then
  if [[ "$REALITY_SHORT_ID" == "a1b2c3d4" || ${#REALITY_SHORT_ID} -lt 16 ]]; then
    REALITY_SHORT_ID=""
  fi

  if [[ -z "$REALITY_SHORT_ID" || "${FORCE_NEW_REALITY:-0}" == "1" ]]; then
    REALITY_SHORT_ID="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  fi

  if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" || "${FORCE_NEW_REALITY:-0}" == "1" ]]; then
    if command -v xray >/dev/null 2>&1; then
      REALITY_KEYS="$(xray x25519)"
    elif command -v docker >/dev/null 2>&1; then
      REALITY_KEYS="$(docker run --rm ghcr.io/xtls/xray-core:latest x25519)"
    else
      echo "xray or docker is required to generate REALITY keys" >&2
      exit 1
    fi

    REALITY_PRIVATE_KEY="$(printf '%s\n' "$REALITY_KEYS" | awk -F': ' '/PrivateKey|Private key/ {print $2; exit}')"
    REALITY_PUBLIC_KEY="$(printf '%s\n' "$REALITY_KEYS" | awk -F': ' '/PublicKey|Public key/ {print $2; exit}')"

    if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
      echo "Failed to parse REALITY keys from xray x25519 output" >&2
      exit 1
    fi
  fi
fi

mkdir -p "$ROOT_DIR/config"

if [[ "$XRAY_MODE" == "cdn-ws" ]]; then
  cat > "$CONFIG_FILE" <<EOF
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

  cat > "$NGINX_CONFIG_FILE" <<EOF
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
else
  CLIENT_FLOW_LINE=""
  TRANSPORT_SETTINGS=""

  case "$XRAY_MODE" in
    tcp)
      CLIENT_FLOW_LINE='            "flow": "xtls-rprx-vision",'
      TRANSPORT_SETTINGS='        "network": "tcp",
        "security": "reality",'
      ;;
    xhttp)
      TRANSPORT_SETTINGS='        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "'"$XHTTP_PATH"'"
        },'
      ;;
    grpc)
      TRANSPORT_SETTINGS='        "network": "grpc",
        "security": "reality",
        "grpcSettings": {
          "serviceName": "'"$GRPC_SERVICE_NAME"'"
        },'
      ;;
  esac

  cat > "$CONFIG_FILE" <<EOF
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
$CLIENT_FLOW_LINE
            "email": "default@xray.local"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
$TRANSPORT_SETTINGS
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
  cat > "$NGINX_CONFIG_FILE" <<EOF
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
chmod 644 "$CONFIG_FILE"
chmod 644 "$NGINX_CONFIG_FILE"

{
  printf 'SERVER_HOST=%s\n' "$SERVER_HOST"
  printf 'MODE=%s\n' "$MODE"
  printf 'XRAY_PORT=%s\n' "$XRAY_PORT"
  printf 'VLESS_UUID=%s\n' "$VLESS_UUID"
  printf 'VLESS_TAG=%s\n' "$VLESS_TAG"
  printf 'REALITY_SNI=%s\n' "$REALITY_SNI"
  printf 'REALITY_DEST=%s\n' "$REALITY_DEST"
  printf 'REALITY_FINGERPRINT=%s\n' "$REALITY_FINGERPRINT"
  printf 'REALITY_PRIVATE_KEY=%s\n' "$REALITY_PRIVATE_KEY"
  printf 'REALITY_PUBLIC_KEY=%s\n' "$REALITY_PUBLIC_KEY"
  printf 'REALITY_SHORT_ID=%s\n' "$REALITY_SHORT_ID"
  printf 'XHTTP_PATH=%s\n' "$XHTTP_PATH"
  printf 'GRPC_SERVICE_NAME=%s\n' "$GRPC_SERVICE_NAME"
  printf 'CDN_WS_PATH=%s\n' "$CDN_WS_PATH"
  printf 'CDN_PORT=%s\n' "$CDN_PORT"
  printf 'LOGLEVEL=%s\n' "$LOGLEVEL"
  printf 'TELEGRAM_CHAT_ADMIN=%s\n' "$TELEGRAM_CHAT_ADMIN"
  printf 'TELEGRAM_BOT_TOKEN=%s\n' "$TELEGRAM_BOT_TOKEN"
  printf 'GAMMA_PROJECT_DIR_HOST=%s\n' "$GAMMA_PROJECT_DIR_HOST"
  printf 'REALITY_ALERT_COOLDOWN_SECONDS=%s\n' "$REALITY_ALERT_COOLDOWN_SECONDS"
  printf 'REALITY_ALERT_STARTUP_TEST_ENABLED=%s\n' "$REALITY_ALERT_STARTUP_TEST_ENABLED"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo
echo "Created:"
echo "  $ENV_FILE"
echo "  $CONFIG_FILE"
echo "  $NGINX_CONFIG_FILE"
echo "Mode: $MODE ($XRAY_MODE)"
echo
"$ROOT_DIR/scripts/link.sh"
