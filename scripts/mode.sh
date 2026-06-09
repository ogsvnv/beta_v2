#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

SERVER_HOST="${SERVER_HOST:-}"

if [[ -z "$SERVER_HOST" ]]; then
  read -r -p "Server host or IP: " SERVER_HOST
fi

cat <<'MENU'
Select Xray mode:
  1. VLESS + TCP/RAW + REALITY + Vision
  2. VLESS + XHTTP + REALITY
  3. VLESS + gRPC + REALITY
  4. VLESS + WebSocket + CDN
MENU

read -r -p "Mode [1-4]: " MODE

case "$MODE" in
  1 | 2 | 3 | 4) ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 1
    ;;
esac

export MODE
"$ROOT_DIR/scripts/setup.sh" "$SERVER_HOST" "$MODE"

cd "$ROOT_DIR"

echo
echo "Restarting Docker Compose services..."
if docker compose version >/dev/null 2>&1; then
  docker compose restart
elif command -v sudo >/dev/null 2>&1 && sudo docker compose version >/dev/null 2>&1; then
  sudo docker compose restart
else
  echo "Docker Compose is not available. Run manually: docker compose restart" >&2
  exit 1
fi
