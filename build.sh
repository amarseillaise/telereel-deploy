#!/bin/bash
#
# build.sh — Build and deploy script for simple-http-file-server
#
# Obtains Let's Encrypt certificates via certbot, generates Nginx
# reverse proxy config, and deploys the application stack via Docker Compose.
#
# Usage:
#   ./build.sh              — Full build & deploy (obtains certs if needed)
#   ./build.sh build        — Build Docker images only
#   ./build.sh deploy       — Deploy without rebuilding
#   ./build.sh stop         — Stop all services
#   ./build.sh logs         — Tail service logs
#   ./build.sh status       — Show running services
#   ./build.sh renew        — Renew SSL certificates and reload Nginx
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${CYAN}==> $1${NC}"; }

# ── Check prerequisites ──────────────────────────────────────────────
check_prerequisites() {
    log_step "Checking prerequisites..."

    local missing=()

    command -v docker   >/dev/null 2>&1 || missing+=("docker")
    command -v envsubst >/dev/null 2>&1 || missing+=("envsubst (gettext)")

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    if ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose V2 is required (docker compose, not docker-compose)"
        exit 1
    fi

    log_info "All prerequisites satisfied"
}

# ── Load environment ─────────────────────────────────────────────────
load_env() {
    if [ ! -f .env ]; then
        log_error ".env file not found."
        log_error "Create it manually based on .env.example:"
        log_error "  cp .env.example .env"
        log_error "  # then edit .env with your values"
        exit 1
    fi

    set -a
    source .env
    set +a

    export SERVER_PORT="${SERVER_PORT:-8080}"
    export CONTENT_DIR="${CONTENT_DIR:-./content}"
    export DOMAIN="${DOMAIN:?DOMAIN is required in .env}"
    export CERTBOT_EMAIL="${CERTBOT_EMAIL:?CERTBOT_EMAIL is required in .env}"

    log_info "Config: SERVER_PORT=${SERVER_PORT}, DOMAIN=${DOMAIN}, EMAIL=${CERTBOT_EMAIL}"
}

# ── Obtain SSL certificate via certbot ────────────────────────────────
setup_ssl() {
    local cert_path="$SCRIPT_DIR/certbot/conf/live/${DOMAIN}/fullchain.pem"

    if [ -f "$cert_path" ]; then
        log_info "SSL certificate found for ${DOMAIN} — skipping"
        return 0
    fi

    mkdir -p "$SCRIPT_DIR/certbot/conf" "$SCRIPT_DIR/certbot/www"

    log_step "Obtaining SSL certificate from Let's Encrypt for: ${DOMAIN}"
    log_warn "Port 80 must be accessible from the internet for the ACME challenge"

    docker run --rm \
        -p 80:80 \
        -v "$SCRIPT_DIR/certbot/conf:/etc/letsencrypt" \
        -v "$SCRIPT_DIR/certbot/www:/var/www/certbot" \
        certbot/certbot certonly \
            --standalone \
            --non-interactive \
            --agree-tos \
            --email "${CERTBOT_EMAIL}" \
            --domain "${DOMAIN}" \
            --preferred-challenges http

    log_info "SSL certificate obtained successfully"
}

# ── Renew SSL certificates ────────────────────────────────────────────
do_renew() {
    log_step "Renewing SSL certificates..."

    docker compose run --rm certbot renew

    log_info "Reloading Nginx with new certificates..."
    docker compose exec nginx nginx -s reload

    log_info "SSL renewal complete"
}

# ── Generate Nginx config from template ───────────────────────────────
setup_nginx() {
    local template="$SCRIPT_DIR/nginx/nginx.conf.template"
    local output="$SCRIPT_DIR/nginx/nginx.conf"

    if [ ! -f "$template" ]; then
        log_error "Nginx template not found: $template"
        exit 1
    fi

    log_step "Generating Nginx configuration..."

    envsubst '${SERVER_PORT} ${DOMAIN}' < "$template" > "$output"

    log_info "Nginx config written to nginx/nginx.conf"
}

# ── Create required directories ───────────────────────────────────────
setup_dirs() {
    mkdir -p "$SCRIPT_DIR/content"
    log_info "Content directory ready"
}

# ── Docker Compose helpers ────────────────────────────────────────────
do_build() {
    log_step "Building Docker images..."
    docker compose build
    log_info "Build complete"
}

do_deploy() {
    log_step "Starting services..."
    docker compose up -d

    log_info "Waiting for health checks..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if docker compose ps --format json 2>/dev/null | grep -q '"healthy"'; then
            break
        fi
        sleep 2
        retries=$((retries - 1))
    done

    echo ""
    docker compose ps
    echo ""
    log_info "==========================================="
    log_info "  Deployment complete!"
    log_info "  HTTPS : https://${DOMAIN}"
    log_info "  HTTP  : http://${DOMAIN}  (→ redirects to HTTPS)"
    log_info "  App internal port: ${SERVER_PORT}"
    log_info "==========================================="
}

do_stop() {
    log_step "Stopping services..."
    docker compose down --remove-orphans
    log_info "All services stopped"
}

do_logs() {
    docker compose logs -f --tail=100
}

do_status() {
    docker compose ps
}

# ── Full build & deploy pipeline ──────────────────────────────────────
full_pipeline() {
    check_prerequisites
    load_env
    setup_ssl
    setup_nginx
    setup_dirs
    do_build
    do_deploy
}

# ── Entry point ───────────────────────────────────────────────────────
main() {
    echo "=================================================="
    echo "  Simple HTTP File Server — Build & Deploy"
    echo "=================================================="
    echo ""

    case "${1:-}" in
        build)
            load_env
            setup_nginx
            do_build
            ;;
        deploy)
            load_env
            setup_ssl
            setup_nginx
            setup_dirs
            do_deploy
            ;;
        stop)
            do_stop
            ;;
        logs)
            do_logs
            ;;
        status)
            do_status
            ;;
        renew)
            load_env
            do_renew
            ;;
        *)
            full_pipeline
            ;;
    esac
}

main "$@"
