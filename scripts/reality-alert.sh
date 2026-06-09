#!/usr/bin/env sh
set -eu

: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required}"
: "${TELEGRAM_CHAT_ADMIN:?TELEGRAM_CHAT_ADMIN is required}"

XRAY_CONTAINER="${XRAY_CONTAINER:-beta-xray}"
PROJECT_DIR="${BETA_PROJECT_DIR:-/beta}"
PROJECT_DIR_HOST="${BETA_PROJECT_DIR_HOST:-/beta}"
ENV_FILE="${PROJECT_DIR}/.env"
MATCH_PATTERN="${REALITY_ALERT_PATTERN:-REALITY: processed invalid connection}"
MATCH_REASON_PATTERN="${REALITY_ALERT_REASON_PATTERN:-failed to read client hello}"
COOLDOWN_SECONDS="${REALITY_ALERT_COOLDOWN_SECONDS:-300}"
LOG_SINCE="${REALITY_ALERT_LOG_SINCE:-0s}"
LAST_ALERT_FILE="${REALITY_ALERT_LAST_ALERT_FILE:-/tmp/reality-alert-last}"
STARTUP_TEST_ENABLED="${REALITY_ALERT_STARTUP_TEST_ENABLED:-1}"
RESTART_JOB_IMAGE="${REALITY_ALERT_RESTART_JOB_IMAGE:-beta-reality-alert:latest}"

send_telegram_message() {
  message="$1"
  response_file="$(mktemp)"

  http_code="$(
    curl -sS \
      -o "$response_file" \
      -w "%{http_code}" \
      -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ADMIN}" \
      --data-urlencode "text=${message}" \
      -d "disable_web_page_preview=true" || printf '000'
  )"

  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    rm -f "$response_file"
    return 0
  fi

  printf '%s' "Telegram sendMessage failed: http=${http_code}, response=" >&2
  cat "$response_file" >&2
  printf '\n' >&2
  rm -f "$response_file"
  return 1
}

send_startup_test() {
  message="✅ Gamma alert bot started
SERVER_HOST=${SERVER_HOST:-unknown}
MODE=${MODE:-unknown}
XRAY_PORT=${XRAY_PORT:-unknown}
VLESS_TAG=${VLESS_TAG:-unknown}

Status:
Server or alert container restarted.
Log monitoring is active."

  send_telegram_message "$message"
}

generate_new_port() {
  random_number="$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')"
  printf '%s\n' $((50000 + random_number % 10000))
}

update_env_value() {
  key="$1"
  value="$2"

  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

build_vless_link() {
  mode="${MODE:-1}"
  xhttp_path="${XHTTP_PATH:-/xhttp}"
  cdn_ws_path="${CDN_WS_PATH:-/ray}"

  case "$mode" in
    1 | tcp | raw | vision)
      query="flow=xtls-rprx-vision&type=tcp&headerType=none"
      ;;
    2 | xhttp)
      encoded_xhttp_path="$(printf '%s' "$xhttp_path" | sed 's|/|%2F|g')"
      query="type=xhttp&path=${encoded_xhttp_path}"
      ;;
    3 | grpc)
      query="type=grpc&serviceName=${GRPC_SERVICE_NAME:-beta}&mode=gun"
      ;;
    4 | cdn | ws | cdn-ws | websocket)
      encoded_cdn_ws_path="$(printf '%s' "$cdn_ws_path" | sed 's|/|%2F|g')"
      printf 'vless://%s@%s:%s?type=ws&host=%s&path=%s&security=tls&sni=%s#%s\n' \
        "${VLESS_UUID:-unknown}" \
        "${SERVER_HOST:-unknown}" \
        "${CDN_PORT:-443}" \
        "${SERVER_HOST:-unknown}" \
        "$encoded_cdn_ws_path" \
        "${SERVER_HOST:-unknown}" \
        "${VLESS_TAG:-beta}"
      return
      ;;
    *)
      query="flow=xtls-rprx-vision&type=tcp&headerType=none"
      ;;
  esac

  printf 'vless://%s@%s:%s?%s&security=reality&fp=%s&sni=%s&pbk=%s&sid=%s#%s\n' \
    "${VLESS_UUID:-unknown}" \
    "${SERVER_HOST:-unknown}" \
    "${XRAY_PORT:-unknown}" \
    "$query" \
    "${REALITY_FINGERPRINT:-chrome}" \
    "${REALITY_SNI:-www.dropbox.com}" \
    "${REALITY_PUBLIC_KEY:-unknown}" \
    "${REALITY_SHORT_ID:-unknown}" \
    "${VLESS_TAG:-beta}"
}

start_compose_restart_job() {
  job_name="beta-compose-restart-$(date +%s)"

  docker run -d --rm \
    --name "$job_name" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${PROJECT_DIR_HOST}:/beta" \
    -w /beta \
    --entrypoint sh \
    "$RESTART_JOB_IMAGE" \
    -lc 'docker compose down && docker compose up -d' >/dev/null

  printf '%s\n' "Started compose restart job: ${job_name}"
}

rotate_port_and_restart() {
  new_port="$(generate_new_port)"
  while [ "$new_port" = "${XRAY_PORT:-}" ]; do
    new_port="$(generate_new_port)"
  done

  update_env_value "XRAY_PORT" "$new_port"
  XRAY_PORT="$new_port"
  export XRAY_PORT

  vless_link="$(build_vless_link)"

  message="❌ REALITY connection rejected
SERVER_HOST=${SERVER_HOST:-unknown}
MODE=${MODE:-unknown}
XRAY_PORT=${XRAY_PORT}
VLESS_UUID=${VLESS_UUID:-unknown}
VLESS_TAG=${VLESS_TAG:-unknown}
REALITY_SNI=${REALITY_SNI:-unknown}
REALITY_DEST=${REALITY_DEST:-unknown}
REALITY_FINGERPRINT=${REALITY_FINGERPRINT:-unknown}
REALITY_PUBLIC_KEY=${REALITY_PUBLIC_KEY:-unknown}
REALITY_SHORT_ID=${REALITY_SHORT_ID:-unknown}

Reason: ClientHello not received

Action:
XRAY_PORT changed to ${XRAY_PORT}.
Running docker compose down && docker compose up -d in ${PROJECT_DIR_HOST}.

VLESS:
${vless_link}"

  if send_telegram_message "$message"; then
    printf '%s\n' "Sent XRAY_PORT rotation message to Telegram bot"
  else
    printf '%s\n' "Failed to send XRAY_PORT rotation message" >&2
  fi

  start_compose_restart_job
}

watch_logs() {
  docker logs --since "$LOG_SINCE" -f "$XRAY_CONTAINER" 2>&1 | while IFS= read -r line; do
    case "$line" in
      *"$MATCH_PATTERN"*"$MATCH_REASON_PATTERN"*)
        now="$(date +%s)"
        last_alert_at=0
        if [ -f "$LAST_ALERT_FILE" ]; then
          last_alert_at="$(cat "$LAST_ALERT_FILE" 2>/dev/null || printf '0')"
        fi

        if [ "$COOLDOWN_SECONDS" -gt 0 ] && [ $((now - last_alert_at)) -lt "$COOLDOWN_SECONDS" ]; then
          continue
        fi

        if rotate_port_and_restart; then
          printf '%s\n' "$now" > "$LAST_ALERT_FILE"
          printf '%s\n' "Handled REALITY rejection event"
        else
          printf '%s\n' "Failed to handle REALITY rejection event" >&2
        fi
        ;;
    esac
  done
}

printf '%s\n' "Watching Docker logs for ${XRAY_CONTAINER}"

if [ "$STARTUP_TEST_ENABLED" = "1" ]; then
  if send_startup_test; then
    printf '%s\n' "Sent startup test message to Telegram bot"
  else
    printf '%s\n' "Failed to send startup test message" >&2
  fi
fi

while :; do
  watch_logs || true
  sleep 5
done
