#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo ".env not found. Run: ./scripts/setup.sh your-domain-or-ip" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

SERVER_HOST="${SERVER_HOST:?SERVER_HOST is not set}"
XRAY_PORT="${XRAY_PORT:-8443}"
MODE="${MODE:-${XRAY_MODE:-1}}"
VLESS_UUID="${VLESS_UUID:?VLESS_UUID is not set}"
REALITY_SNI="${REALITY_SNI:-www.dropbox.com}"
REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-chrome}"
TAG="${VLESS_TAG:-home-xray}"
XHTTP_PATH="${XHTTP_PATH:-/xhttp}"
GRPC_SERVICE_NAME="${GRPC_SERVICE_NAME:-home-xray}"
CDN_WS_PATH="${CDN_WS_PATH:-/ray}"
CDN_PORT="${CDN_PORT:-443}"

case "$MODE" in
  1 | tcp | raw | vision)
    REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:?REALITY_PUBLIC_KEY is not set}"
    REALITY_SHORT_ID="${REALITY_SHORT_ID:?REALITY_SHORT_ID is not set}"
    QUERY="flow=xtls-rprx-vision&type=tcp&headerType=none"
    LINK="vless://${VLESS_UUID}@${SERVER_HOST}:${XRAY_PORT}?${QUERY}&security=reality&fp=${REALITY_FINGERPRINT}&sni=${REALITY_SNI}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}#${TAG}"
    ;;
  2 | xhttp)
    REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:?REALITY_PUBLIC_KEY is not set}"
    REALITY_SHORT_ID="${REALITY_SHORT_ID:?REALITY_SHORT_ID is not set}"
    ENCODED_XHTTP_PATH="${XHTTP_PATH//\//%2F}"
    QUERY="type=xhttp&path=${ENCODED_XHTTP_PATH}"
    LINK="vless://${VLESS_UUID}@${SERVER_HOST}:${XRAY_PORT}?${QUERY}&security=reality&fp=${REALITY_FINGERPRINT}&sni=${REALITY_SNI}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}#${TAG}"
    ;;
  3 | grpc)
    REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:?REALITY_PUBLIC_KEY is not set}"
    REALITY_SHORT_ID="${REALITY_SHORT_ID:?REALITY_SHORT_ID is not set}"
    QUERY="type=grpc&serviceName=${GRPC_SERVICE_NAME}&mode=gun"
    LINK="vless://${VLESS_UUID}@${SERVER_HOST}:${XRAY_PORT}?${QUERY}&security=reality&fp=${REALITY_FINGERPRINT}&sni=${REALITY_SNI}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}#${TAG}"
    ;;
  4 | cdn | ws | cdn-ws | websocket)
    ENCODED_CDN_WS_PATH="${CDN_WS_PATH//\//%2F}"
    QUERY="type=ws&host=${SERVER_HOST}&path=${ENCODED_CDN_WS_PATH}"
    LINK="vless://${VLESS_UUID}@${SERVER_HOST}:${CDN_PORT}?${QUERY}&security=tls&sni=${SERVER_HOST}#${TAG}"
    ;;
  *)
    echo "Unknown MODE: $MODE" >&2
    exit 1
    ;;
esac

echo "VLESS link:"
echo "$LINK"
