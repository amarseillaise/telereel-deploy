# Deploy — Docker + Nginx + Let's Encrypt

Развёртывание telereel-fileserver и telereel-bot с Nginx reverse proxy и автоматическими TLS-сертификатами через Let's Encrypt.

## Архитектура

```
Internet → :80  (HTTP)  → Nginx → 301 redirect → :443
Internet → :443 (HTTPS) → Nginx (TLS termination) → app:8080 (HTTP) → Go fileserver

Telegram API ←→ bot (long polling) → app:8080 (HTTP) → Go fileserver
```

- Go fileserver работает на внутреннем порту (HTTP) внутри Docker-сети
- Telegram bot общается с fileserver напрямую по внутренней Docker-сети
- Nginx терминирует TLS на порту 443
- Certbot автоматически обновляет сертификаты каждые 12 часов

## Требования

- Docker + Docker Compose V2
- `envsubst` (пакет `gettext`)
- Домен, направленный на сервер (для Let's Encrypt)
- Открытый порт 80 (для ACME challenge)

## Быстрый старт

```bash
# 1. Инициализировать подмодули
git submodule update --init --recursive

# 2. Настроить окружение
cp .env.example .env
# отредактировать: DOMAIN, CERTBOT_EMAIL, TELETOKEN

# 3. Положить cookies.txt для Instagram
cp /path/to/cookies.txt ./cookies.txt

# 4. Собрать и запустить
./build.sh
```

## Команды build.sh

| Команда            | Описание                                        |
|--------------------|--------------------------------------------------|
| `./build.sh`       | Полный цикл: сертификат → сборка → деплой        |
| `./build.sh build` | Только сборка Docker-образов                     |
| `./build.sh deploy`| Деплой без пересборки                            |
| `./build.sh stop`  | Остановить все сервисы                           |
| `./build.sh logs`  | Смотреть логи (tail -f)                          |
| `./build.sh status`| Статус контейнеров                               |
| `./build.sh renew` | Обновить SSL-сертификаты и перезагрузить Nginx   |

## Конфигурация (.env)

| Переменная     | Описание                                 | По умолчанию |
|----------------|------------------------------------------|--------------|
| SERVER_PORT    | Внутренний порт Go-сервера               | 8080         |
| CONTENT_DIR    | Директория для видео                     | ./content    |
| DOMAIN         | Домен для Nginx и Let's Encrypt          | —            |
| CERTBOT_EMAIL  | Email для уведомлений Let's Encrypt      | —            |
| TELETOKEN      | Токен Telegram-бота (от @BotFather)      | —            |
| UPDATE_YTDLP   | Обновлять yt-dlp при старте контейнера   | false        |

## Структура

```
deploy/
├── build.sh                 # Скрипт развёртывания
├── Dockerfile               # Multi-stage сборка (fileserver + bot)
├── docker-compose.yml       # Оркестрация: app + bot + nginx + certbot
├── nginx/
│   └── nginx.conf.template  # Шаблон конфигурации Nginx
├── telereel-fileserver/     # Подмодуль: Go HTTP file server
├── telereel-bot/            # Подмодуль: Telegram bot
├── .env.example             # Шаблон переменных окружения
├── .gitignore
└── README.md
```
