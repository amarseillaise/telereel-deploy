# ── Build: fileserver ─────────────────────────────────────────────────
FROM golang:1.21-alpine AS builder-fileserver

WORKDIR /app

COPY telereel-fileserver/go.mod telereel-fileserver/go.sum ./
RUN go mod download

COPY telereel-fileserver/cmd/ ./cmd/
COPY telereel-fileserver/internal/ ./internal/
COPY telereel-fileserver/pkg/ ./pkg/

RUN go build -o server cmd/server/main.go

# ── Build: bot ────────────────────────────────────────────────────────
FROM golang:1.24-alpine AS builder-bot

WORKDIR /app

COPY telereel-bot/go.mod telereel-bot/go.sum ./
RUN go mod download

COPY telereel-bot/main.go ./
COPY telereel-bot/bot/ ./bot/
COPY telereel-bot/services/ ./services/

RUN go build -o bot main.go

# ── Target: fileserver runtime ────────────────────────────────────────
FROM alpine:latest AS fileserver

RUN apk add --no-cache \
    python3 \
    py3-pip \
    ffmpeg \
    && pip3 install --break-system-packages yt-dlp

WORKDIR /app

COPY --from=builder-fileserver /app/server .

RUN mkdir -p /app/content && \
    printf '#!/bin/sh\nset -e\nif [ "${UPDATE_YTDLP:-false}" = "true" ]; then\n  echo "[entrypoint] Updating yt-dlp..."\n  pip3 install --break-system-packages --upgrade yt-dlp 2>&1 | tail -1\n  echo "[entrypoint] yt-dlp version: $(yt-dlp --version)"\nfi\nexec "$@"\n' > /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

EXPOSE 8080

ENV CONTENT_DIR=/app/content

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["./server"]

# ── Target: bot runtime ──────────────────────────────────────────────
FROM alpine:latest AS bot

RUN apk add --no-cache ca-certificates

WORKDIR /app

COPY --from=builder-bot /app/bot .

CMD ["./bot"]
