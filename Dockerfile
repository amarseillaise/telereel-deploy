# ── Stage 1: Build Go binary ──────────────────────────────────────────
FROM golang:1.21-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY cmd/ ./cmd/
COPY internal/ ./internal/
COPY pkg/ ./pkg/

RUN go build -o server cmd/server/main.go

# ── Stage 2: Runtime ──────────────────────────────────────────────────
FROM alpine:latest

RUN apk add --no-cache \
    python3 \
    py3-pip \
    ffmpeg \
    && pip3 install --break-system-packages yt-dlp

WORKDIR /app

COPY --from=builder /app/server .

RUN mkdir -p /app/content

EXPOSE 8080

ENV CONTENT_DIR=/app/content

CMD ["./server"]
