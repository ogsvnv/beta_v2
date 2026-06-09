# Xray VLESS Docker Compose

Минимальный Xray-сервер в Docker Compose с 3x-ui как главным Xray manager и управляемыми режимами VLESS REALITY, CDN/WebSocket или gRPC + TLS через Caddy.

## Быстрый старт

Репозиторий: [ogsvnv/beta_v2](https://github.com/ogsvnv/beta_v2)

```bash
chmod +x install.sh
./install.sh your-domain.com --tcp
```

Вместо `your-domain.com` можно указать публичный IP сервера.

Для чистого VPS можно использовать установку через `wget`:

```bash
wget -O - https://raw.githubusercontent.com/ogsvnv/beta_v2/main/install.sh | bash
```

Или без диалога:

```bash
wget -O - https://raw.githubusercontent.com/ogsvnv/beta_v2/main/install.sh | bash -s -- --host your-domain.com --tcp
```

Установщик сначала проверит Docker, UFW и `vnstat`, а затем задаст вопросы о названии проекта/VLESS tag, домене/IP и режиме, если они не переданы через переменные окружения или аргументы. После этого он откроет SSH, порт выбранного режима и порт панели 3x-ui, склонирует проект, создаст конфиг и запустит контейнеры.
Также установщик спросит логин/пароль админа 3x-ui, `LOGLEVEL` из списка `info`, `warning`, `error`, `debug`, `none`, а затем `TELEGRAM_CHAT_ADMIN` и `TELEGRAM_BOT_TOKEN`.

Если Docker ставится впервые, установщик добавит пользователя в группу `docker` и остановится. После этого выйдите из SSH-сессии, зайдите снова и повторите ту же команду установки. Это нужно, чтобы новая группа применилась к текущей shell-сессии.
При повторном запуске установка Docker будет пропущена, если `docker compose` уже доступен.
Перед новой установкой скрипт удаляет старый compose-stack, контейнеры `beta-*`, неиспользуемые Docker resources и папку проекта.

## Варианты установки

Диалоговый режим:

```bash
wget -O - https://raw.githubusercontent.com/ogsvnv/beta_v2/main/install.sh | bash
```

Установка конкретного режима:

```bash
wget -O - https://raw.githubusercontent.com/ogsvnv/beta_v2/main/install.sh | bash -s -- --host example.com --grpc
wget -O - https://raw.githubusercontent.com/ogsvnv/beta_v2/main/install.sh | bash -s -- --host example.com --grpc-tls
wget -O - https://raw.githubusercontent.com/ogsvnv/beta_v2/main/install.sh | bash -s -- --host example.com --grpc --project-name beta
wget -O - https://raw.githubusercontent.com/ogsvnv/beta_v2/main/install.sh | bash -s -- --host example.com --grpc --loglevel warning
wget -O - https://raw.githubusercontent.com/ogsvnv/beta_v2/main/install.sh | bash -s -- --host example.com --grpc --xui-username admin --xui-password secret
```

Локальный запуск из уже скачанного репозитория:

```bash
./install.sh example.com --grpc-tls
```

## Что создается

- `.env` с `SERVER_HOST`, внешним `XRAY_PORT`, UUID клиента и логином/паролем 3x-ui.
- тестовый VLESS-клиент `test@beta.local` в 3x-ui.
- `config/Caddyfile` для режима gRPC + TLS через Caddy.
- `config/xui-inbound.json` с payload для создания рабочего inbound/client в 3x-ui через API.
- `config/xui-xray-template.json` с Xray template для 3x-ui, включая выбранный `LOGLEVEL`.
- `docker-compose.yml`, скопированный из шаблона выбранного режима.
- `compose/docker-compose.mode1-tcp-reality.yml`.
- `compose/docker-compose.mode2-xhttp-reality.yml`.
- `compose/docker-compose.mode3-grpc-reality.yml`.
- `compose/docker-compose.mode4-cdn-ws.yml`.
- `compose/docker-compose.mode5-grpc-tls-caddy.yml`.
- VLESS-ссылка для выбранного режима.
- REALITY private/public keypair и short id.
- Docker-сервис 3x-ui как главный Xray manager; для `MODE=5` дополнительно Caddy.

## Команды

```bash
docker compose up -d
docker compose logs -f
docker compose down
./install.sh your-domain.com --grpc
```

## 3x-ui

Во все варианты compose добавлен контейнер `beta-3x-ui` на образе `ghcr.io/mhsanaei/3x-ui:latest`. 3x-ui является главным владельцем рабочего inbound: установщик настраивает логин панели, обновляет Xray template с выбранным `LOGLEVEL` и создаёт inbound/client через API 3x-ui, поэтому пользователь `test@beta.local` виден в панели и статистика считается в 3x-ui.

По умолчанию панель публикуется на порту `2053`:

```text
http://your-domain.com:2053/panel
```

Порт можно изменить перед генерацией конфига:

```bash
XUI_PORT=3053 ./install.sh your-domain.com --tcp
```

Данные панели сохраняются в Docker volumes `x-ui-data` и `x-ui-cert`. Логин и пароль панели выводятся в конце установки и сохраняются в `.env` как `XUI_USERNAME` и `XUI_PASSWORD`.

## Telegram

Установщик может сохранить Telegram-настройки в `.env`:

Добавьте в `.env`:

```env
TELEGRAM_CHAT_ADMIN=-1001234567890
TELEGRAM_BOT_TOKEN=1234567890:replace-with-token
BETA_PROJECT_DIR_HOST=/beta
REALITY_ALERT_COOLDOWN_SECONDS=300
REALITY_ALERT_STARTUP_TEST_ENABLED=1
```

После перевода inbound под 3x-ui отдельный `beta-reality-alert` контейнер больше не запускается.

## Режимы

Режим выбирается в `.env`:

```env
MODE=1
```

Доступны пять значений.

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
GRPC_SERVICE_NAME=beta
```

Ссылка содержит:

```text
type=grpc&serviceName=beta&mode=gun&security=reality
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

### MODE=5

VLESS + gRPC + TLS через Caddy.

В этом режиме Caddy принимает публичный HTTPS на `80/443`, выпускает и продлевает TLS-сертификат для домена, затем проксирует gRPC-запросы на Xray внутри `beta-3x-ui` по h2c внутри docker-сети:

```text
Caddy :443 TLS example.com
        ↓ gRPC /beta/Tun
3x-ui/Xray :10000 h2c gRPC
```

По умолчанию используется service name:

```env
GRPC_SERVICE_NAME=beta
```

Фактический gRPC path для Xray будет:

```text
/beta/Tun
```

Ссылка содержит:

```text
type=grpc&serviceName=beta&mode=gun&security=tls&sni=example.com
```

Пример compose-схемы для этого режима:

```yaml
services:
  caddy:
    image: caddy:2
    container_name: beta-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - 3x-ui

  3x-ui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: beta-3x-ui
    restart: unless-stopped
    expose:
      - "10000"
    ports:
      - "${XUI_PORT:-2053}:2053/tcp"
    volumes:
      - x-ui-data:/etc/x-ui/
      - x-ui-cert:/root/cert/

volumes:
  caddy_data:
  caddy_config:
  x-ui-data:
  x-ui-cert:
```

Сгенерированный `config/Caddyfile`:

```caddyfile
example.com {
  encode zstd gzip

  reverse_proxy /beta/Tun* h2c://beta-3x-ui:10000

  respond "OK" 200
}
```

Выбор режима через аргумент:

```bash
./install.sh example.com --tcp
./install.sh example.com --xhttp
./install.sh example.com --grpc
./install.sh proxy.example.com --cdn
./install.sh example.com --grpc-tls
```

То же самое для `wget`:

```bash
wget -O - https://raw.githubusercontent.com/ogsvnv/beta_v2/main/install.sh | bash -s -- --host example.com --grpc
```

После ручного изменения `MODE` в `.env` проще заново запустить установщик с нужным флагом:

```bash
./install.sh your-domain.com --grpc
```

## Порт

По умолчанию наружу публикуется порт `8443`:

```bash
./install.sh your-domain.com --tcp
```

Для `MODE=1/2/3` порт `XRAY_PORT` публикуется напрямую в контейнер `beta-3x-ui`, где Xray управляется панелью и слушает внутренний порт `443`.

Чтобы поменять внешний порт, задайте `XRAY_PORT`:

```bash
XRAY_PORT=9443 ./install.sh your-domain.com --tcp
```

Откройте выбранный TCP-порт, например `8443/tcp`, в firewall/security group сервера.

Для `MODE=4` обычно открывается `80/tcp` на VPS, потому что Cloudflare принимает HTTPS на `443`, а к origin может ходить по HTTP на `80`. Клиент при этом подключается к `proxy.example.com:443`.

Для `MODE=5` откройте `80/tcp` и `443/tcp`: Caddy использует `80` для выпуска/обновления сертификата и `443` для клиентского TLS/gRPC.

## REALITY параметры

По умолчанию используется:

```env
REALITY_SNI=www.dropbox.com
REALITY_DEST=www.dropbox.com:443
REALITY_FINGERPRINT=chrome
```

Итоговая ссылка будет похожа на:

```text
vless://uuid@host:8443?flow=xtls-rprx-vision&type=tcp&headerType=none&security=reality&fp=chrome&sni=www.dropbox.com&pbk=public-key&sid=short-id#beta
```

Для XHTTP ссылка будет содержать `type=xhttp&path=%2Fxhttp`, для gRPC - `type=grpc&serviceName=beta&mode=gun`.
Для gRPC + TLS через Caddy ссылка будет содержать `type=grpc&serviceName=beta&mode=gun&security=tls`.

Чтобы пересоздать UUID:

```bash
FORCE_NEW_UUID=1 ./install.sh your-domain.com --tcp
```

Чтобы пересоздать REALITY ключи и `sid`:

```bash
FORCE_NEW_REALITY=1 ./install.sh your-domain.com --tcp
```

## Важно

Для `MODE=1/2/3/4` inbound-порт публикуется прямо из контейнера `beta-3x-ui`, а рабочий Xray управляется панелью.

Для `MODE=5` TLS завершает Caddy, а Xray внутри `beta-3x-ui` получает h2c gRPC на внутреннем порту `10000`. REALITY-параметры в клиентской ссылке не используются.

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

Если хотите режим `Full`, понадобится добавить TLS на origin. В текущей конфигурации `MODE=4` рассчитан на простой HTTP origin за Cloudflare.

### 5. Запустите сервер в MODE=4

На чистом VPS:

```bash
wget -O - https://raw.githubusercontent.com/ogsvnv/beta_v2/main/install.sh | bash -s -- --host proxy.example.com --cdn
```

Если проект уже установлен:

```bash
./install.sh proxy.example.com --cdn
```

Для явного указания origin-порта:

```bash
XRAY_PORT=80 ./install.sh proxy.example.com --cdn
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
./install.sh proxy.example.com --cdn
```

Должна выдать ссылку вида:

```text
vless://uuid@proxy.example.com:443?type=ws&host=proxy.example.com&path=%2Fray&security=tls&sni=proxy.example.com#beta
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
