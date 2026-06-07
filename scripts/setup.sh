#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
CONFIG_FILE="$ROOT_DIR/config/xray.json"

SERVER_HOST="${1:-${SERVER_HOST:-}}"
MODE="${2:-${MODE:-${XRAY_MODE:-1}}}"
XRAY_PORT="${XRAY_PORT:-8443}"
VLESS_UUID="${VLESS_UUID:-}"
VLESS_TAG="${VLESS_TAG:-home-xray}"
REALITY_SNI="${REALITY_SNI:-www.dropbox.com}"
REALITY_DEST="${REALITY_DEST:-${REALITY_SNI}:443}"
REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-chrome}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"
XHTTP_PATH="${XHTTP_PATH:-/xhttp}"
GRPC_SERVICE_NAME="${GRPC_SERVICE_NAME:-home-xray}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
  SERVER_HOST="${1:-${SERVER_HOST:-}}"
  MODE="${2:-${MODE:-${XRAY_MODE:-1}}}"
  XRAY_PORT="${XRAY_PORT:-8443}"
  VLESS_UUID="${VLESS_UUID:-}"
  VLESS_TAG="${VLESS_TAG:-home-xray}"
  REALITY_SNI="${REALITY_SNI:-www.dropbox.com}"
  REALITY_DEST="${REALITY_DEST:-${REALITY_SNI}:443}"
  REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-chrome}"
  REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
  REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
  REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"
  XHTTP_PATH="${XHTTP_PATH:-/xhttp}"
  GRPC_SERVICE_NAME="${GRPC_SERVICE_NAME:-home-xray}"
fi

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
  *)
    echo "Unknown MODE: $MODE" >&2
    echo "Use one of: 1, 2, 3" >&2
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

mkdir -p "$ROOT_DIR/config"

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
chmod 644 "$CONFIG_FILE"

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
  printf 'LOGLEVEL=%s\n' "$LOGLEVEL"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo
echo "Created:"
echo "  $ENV_FILE"
echo "  $CONFIG_FILE"
echo "Mode: $MODE ($XRAY_MODE)"
echo
"$ROOT_DIR/scripts/link.sh"
