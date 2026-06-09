# Xray VLESS Docker Compose

Минимальный Xray-сервер в Docker Compose с Nginx-прокси и управляемыми режимами VLESS REALITY или CDN/WebSocket.

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
- `config/nginx.conf` с TCP-прокси для REALITY или HTTP/WebSocket reverse proxy для CDN-режима.
- `config/xray.json` с inbound VLESS REALITY на внутреннем порту `443` или VLESS WebSocket на `10000`.
- VLESS-ссылка для выбранного режима.
- REALITY private/public keypair и short id.

## Команды

```bash
docker compose up -d
docker compose logs -f
docker compose down
./scripts/link.sh
```

## Telegram alert

В compose добавлен контейнер `gamma-reality-alert`. Он читает логи `gamma-xray` и при строке вида `REALITY: processed invalid connection ... failed to read client hello` отправляет сообщение в Telegram.

Добавьте в `.env`:

```env
TELEGRAM_CHAT_ADMIN=-1001234567890
TELEGRAM_BOT_TOKEN=1234567890:replace-with-token
GAMMA_PROJECT_DIR_HOST=/gamma
REALITY_ALERT_COOLDOWN_SECONDS=300
REALITY_ALERT_STARTUP_TEST_ENABLED=1
```

`REALITY_ALERT_COOLDOWN_SECONDS=300` означает, что логи отслеживаются постоянно, но сообщение отправляется не чаще одного раза в 5 минут.
`REALITY_ALERT_STARTUP_TEST_ENABLED=1` включает тестовое сообщение при старте alert-контейнера, например после перезапуска сервера.
При `failed to read client hello` alert-контейнер меняет `XRAY_PORT` на случайный порт `50000-59999`, отправляет новый `vless://` в Telegram и запускает `docker compose down && docker compose up -d` в каталоге `GAMMA_PROJECT_DIR_HOST`.

После изменения `.env` перезапустите alert-контейнер:

```bash
docker compose up -d --build reality-alert
```

## Режимы

Режим выбирается в `.env`:

```env
MODE=1
```

Доступны четыре значения.

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

### MODE=4

VLESS + WebSocket + CDN.

Этот режим предназначен для домена, который проксируется через CDN, например Cloudflare. В отличие от `MODE=1/2/3`, здесь не используется REALITY: CDN принимает обычный HTTPS/WebSocket трафик на своем edge, затем отправляет WebSocket-запрос на VPS. Поэтому клиентская ссылка использует `security=tls&type=ws`, а не `security=reality`.

По умолчанию используется путь:

```env
CDN_WS_PATH=/ray
```

Клиентский порт CDN:

```env
CDN_PORT=443
```

Origin-порт на VPS по умолчанию для свежей установки `MODE=4`:

```env
XRAY_PORT=80
```

Ссылка содержит:

```text
type=ws&host=proxy.example.com&path=%2Fray&security=tls&sni=proxy.example.com
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
./scripts/setup.sh proxy.example.com 4
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

Для `MODE=4` обычно открывается `80/tcp` на VPS, потому что Cloudflare принимает HTTPS на `443`, а к origin может ходить по HTTP на `80`. Клиент при этом подключается к `proxy.example.com:443`.

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

Для `MODE=4` наоборот используется обычный HTTP/WebSocket reverse proxy в Nginx. REALITY-параметры в клиентской ссылке не используются.

## Настройка CDN-режима через Cloudflare

Ниже пример для домена `example.com` и поддомена `proxy.example.com`.

### 1. Подключите домен к Cloudflare

1. Зайдите в Cloudflare.
2. Нажмите `Add a domain` / `Add site`.
3. Добавьте основной домен:

```text
example.com
```

4. Cloudflare покажет два nameserver'а.
5. Откройте панель регистратора, где покупали домен.
6. Замените nameserver'ы домена на те, которые дал Cloudflare.
7. Дождитесь статуса `Active` в Cloudflare.

### 2. Добавьте DNS-запись

Откройте:

```text
Websites -> example.com -> DNS -> Records -> Add record
```

Добавьте запись:

```text
Type: A
Name: proxy
IPv4 address: IP_ВАШЕГО_VPS
Proxy status: Proxied
TTL: Auto
```

Важно: статус должен быть `Proxied`, оранжевое облако. Если стоит `DNS only`, трафик пойдет напрямую на VPS, без CDN.

### 3. Включите WebSocket в Cloudflare

Откройте:

```text
Websites -> example.com -> Network
```

Проверьте, что `WebSockets` включены. Обычно они включены по умолчанию.

### 4. Настройте SSL/TLS в Cloudflare

Для простого запуска с текущим `MODE=4`:

```text
Websites -> example.com -> SSL/TLS -> Overview -> Flexible
```

В этом варианте клиент подключается к Cloudflare по HTTPS на `443`, а Cloudflare подключается к VPS по HTTP на `80`.

Если хотите режим `Full`, понадобится добавить TLS-сертификат на origin nginx и поменять compose/nginx на HTTPS origin. В текущей конфигурации `MODE=4` рассчитан на простой HTTP origin за Cloudflare.

### 5. Запустите сервер в MODE=4

На чистом VPS:

```bash
SERVER_HOST=proxy.example.com MODE=4 ./scripts/start.sh
```

Если проект уже установлен:

```bash
./scripts/setup.sh proxy.example.com 4
docker compose up -d
./scripts/link.sh
```

Для явного указания origin-порта:

```bash
XRAY_PORT=80 ./scripts/setup.sh proxy.example.com 4
docker compose up -d
./scripts/link.sh
```

### 6. Откройте firewall

Для `MODE=4` откройте на VPS:

```bash
sudo ufw allow 80/tcp
sudo ufw reload
```

Если у VPS есть security group у провайдера, там тоже должен быть открыт `80/tcp`.

Порт `443/tcp` на VPS для этого варианта не обязателен: `443` принимает Cloudflare.

### 7. Проверьте ссылку

Команда:

```bash
./scripts/link.sh
```

Должна выдать ссылку вида:

```text
vless://uuid@proxy.example.com:443?type=ws&host=proxy.example.com&path=%2Fray&security=tls&sni=proxy.example.com#home-xray
```

В клиенте должны быть параметры:

```text
Address: proxy.example.com
Port: 443
UUID: из .env
Transport: ws / websocket
Path: /ray
Host: proxy.example.com
TLS: enabled
SNI: proxy.example.com
Security: none внутри VLESS, TLS снаружи
```

### 8. Частые ошибки

Если клиент не подключается:

- Проверьте, что DNS-запись `proxy` в Cloudflare имеет статус `Proxied`.
- Проверьте, что `SSL/TLS` mode в Cloudflare установлен в `Flexible`.
- Проверьте, что в Cloudflare включены `WebSockets`.
- Проверьте, что на VPS открыт `80/tcp`.
- Проверьте, что в клиенте путь точно совпадает с `CDN_WS_PATH`, по умолчанию `/ray`.
- Перезапустите контейнеры после изменения режима:

```bash
docker compose down
docker compose up -d
```
