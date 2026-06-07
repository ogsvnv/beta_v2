# Xray VLESS Docker Compose

Минимальный Xray-сервер в Docker Compose с Nginx TCP-прокси и управляемыми режимами VLESS REALITY.

## Быстрый старт

```bash
chmod +x scripts/*.sh
./scripts/setup.sh your-domain.com
docker compose up -d
./scripts/link.sh
```

Вместо `your-domain.com` можно указать публичный IP сервера.

Для чистого VPS можно использовать предварительный скрипт:

```bash
SERVER_HOST=your-domain.com MODE=1 ./scripts/start.sh
```

Он установит Docker, UFW и `vnstat`, включит сервис `vnstat`, откроет SSH и порт Xray, склонирует проект, создаст конфиг и запустит контейнеры.

## Что создается

- `.env` с `SERVER_HOST`, внешним `XRAY_PORT` и UUID клиента.
- `config/nginx.conf` с TCP-прокси с внешнего порта `8443` на Xray.
- `config/xray.json` с inbound VLESS REALITY на внутреннем порту `443`.
- VLESS-ссылка для выбранного режима.
- REALITY private/public keypair и short id.

## Команды

```bash
docker compose up -d
docker compose logs -f
docker compose down
./scripts/link.sh
```

## Режимы

Режим выбирается в `.env`:

```env
MODE=1
```

Доступны три значения.

### MODE=1

VLESS + TCP/RAW + REALITY + Vision.

Это текущий базовый режим. Трафик идет напрямую поверх TCP, REALITY отвечает за маскировку TLS, а `flow=xtls-rprx-vision` включает Vision. Обычно это самый быстрый и простой вариант для личного сервера: меньше накладных расходов, ниже задержка, проще диагностика. Его стоит выбирать первым, если нет особых ограничений со стороны сети или клиента.

Ссылка содержит:

```text
flow=xtls-rprx-vision&type=tcp&headerType=none&security=reality
```

### MODE=2

VLESS + XHTTP + REALITY.

В этом режиме VLESS использует XHTTP-транспорт. Он выглядит ближе к HTTP-подобному трафику и может быть полезен там, где прямой TCP/RAW работает нестабильно или фильтруется. Подходит только для клиентов, которые поддерживают XHTTP + REALITY.

По умолчанию используется путь:

```env
XHTTP_PATH=/xhttp
```

Ссылка содержит:

```text
type=xhttp&path=%2Fxhttp&security=reality
```

### MODE=3

VLESS + gRPC + REALITY.

В этом режиме VLESS использует gRPC-транспорт. Он может быть удобен в сетях или клиентах, где gRPC работает стабильнее, а также в инфраструктуре, ориентированной на HTTP/2/gRPC. Обычно у него больше накладных расходов, чем у `MODE=1`, поэтому выбирать его стоит осознанно: если клиент или сеть лучше дружит именно с gRPC.

По умолчанию используется service name:

```env
GRPC_SERVICE_NAME=home-xray
```

Ссылка содержит:

```text
type=grpc&serviceName=home-xray&mode=gun&security=reality
```

Интерактивное переключение:

```bash
./scripts/mode.sh
```

Переключение через аргумент:

```bash
./scripts/setup.sh your-domain.com 1
./scripts/setup.sh your-domain.com 2
./scripts/setup.sh your-domain.com 3
```

После ручного изменения `MODE` в `.env` пересоздайте конфиг и перезапустите контейнеры:

```bash
./scripts/setup.sh your-domain.com
docker compose restart
./scripts/link.sh
```

## Порт

По умолчанию наружу публикуется порт `8443`:

```bash
./scripts/setup.sh your-domain.com
docker compose up -d
```

Nginx слушает `8443` внутри контейнера и проксирует TCP-трафик в Xray на `443`.

Чтобы поменять внешний порт, задайте `XRAY_PORT`:

```bash
XRAY_PORT=9443 ./scripts/setup.sh your-domain.com
docker compose up -d
```

Откройте выбранный TCP-порт, например `8443/tcp`, в firewall/security group сервера.

## REALITY параметры

По умолчанию используется:

```env
REALITY_SNI=www.dropbox.com
REALITY_DEST=www.dropbox.com:443
REALITY_FINGERPRINT=chrome
```

Итоговая ссылка будет похожа на:

```text
vless://uuid@host:8443?flow=xtls-rprx-vision&type=tcp&headerType=none&security=reality&fp=chrome&sni=www.dropbox.com&pbk=public-key&sid=short-id#home-xray
```

Для XHTTP ссылка будет содержать `type=xhttp&path=%2Fxhttp`, для gRPC - `type=grpc&serviceName=home-xray&mode=gun`.

Чтобы пересоздать UUID:

```bash
FORCE_NEW_UUID=1 ./scripts/setup.sh your-domain.com
```

Чтобы пересоздать REALITY ключи и `sid`:

```bash
FORCE_NEW_REALITY=1 ./scripts/setup.sh your-domain.com
```

## Важно

Nginx здесь работает как TCP passthrough-прокси. TLS/REALITY обрабатывает Xray, поэтому обычный HTTP reverse proxy для этого конфига не подойдет.
