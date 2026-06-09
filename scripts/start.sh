#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${USER_NAME:-${SUDO_USER:-${USER:-}}}"
REPO_DIR="${REPO_DIR:-gamma}"
SERVER_HOST="${1:-${SERVER_HOST:-}}"
MODE="${2:-${MODE:-1}}"
INPUT_XRAY_PORT="${XRAY_PORT:-}"
XRAY_PORT="${INPUT_XRAY_PORT:-8443}"

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

case "$MODE" in
  1 | 2 | 3 | 4) ;;
  *)
    echo "Unknown MODE: $MODE" >&2
    echo "Use MODE=1, MODE=2, MODE=3 or MODE=4" >&2
    exit 1
    ;;
esac

if [[ "$MODE" == "4" && -z "$INPUT_XRAY_PORT" ]]; then
  XRAY_PORT="80"
fi

if [[ -z "$SERVER_HOST" ]]; then
  read -r -p "Server host or IP: " SERVER_HOST
fi

if [[ -z "$SERVER_HOST" ]]; then
  echo "SERVER_HOST is required" >&2
  exit 1
fi

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

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ogsvnv
sudo usermod -aG docker "$USER_NAME"

echo "=============================="
echo "[4/9] Starting vnStat"
echo "=============================="
sudo systemctl enable vnstat
sudo systemctl start vnstat
sudo systemctl status vnstat --no-pager || true
vnstat || true

echo "=============================="
echo "[5/9] Configuring firewall"
echo "=============================="
sudo ufw allow 22/tcp
sudo ufw allow "$XRAY_PORT/tcp"
sudo ufw --force enable
sudo ufw status verbose

echo "=============================="
echo "[7/9] Creating Xray config"
echo "=============================="
cd "$APP_DIR"
chmod +x scripts/*.sh
MODE="$MODE" XRAY_PORT="$XRAY_PORT" ./scripts/setup.sh "$SERVER_HOST" "$MODE"
sudo chown -R "$USER_NAME:$USER_NAME" "$APP_DIR"

echo "=============================="
echo "[8/9] Starting Docker Compose"
echo "=============================="
sudo docker compose up -d

echo "=============================="
echo "[9/9] VLESS link"
echo "=============================="
./scripts/link.sh
