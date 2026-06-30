#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# Open Source WhatsApp Business Stack — One-shot Setup Script
# Tested on Ubuntu 22.04 / Debian 12
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}  Open Source WhatsApp Business Stack — Setup${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""

# ── 1. Check prerequisites ────────────────────────────────────────────────────
info "Checking prerequisites..."

command -v docker >/dev/null 2>&1 || error "Docker not found. Install it: https://docs.docker.com/engine/install/"
command -v docker compose >/dev/null 2>&1 || \
  docker compose version >/dev/null 2>&1 || \
  error "Docker Compose v2 not found. Install it: https://docs.docker.com/compose/install/"

DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+')
info "Docker version: $DOCKER_VERSION"
success "All prerequisites met."

# ── 2. Create external Docker network for Traefik ─────────────────────────────
info "Creating external Docker network 'web' for Traefik..."
docker network inspect web >/dev/null 2>&1 && \
  warn "Network 'web' already exists, skipping." || \
  docker network create web
success "Network 'web' ready."

# ── 3. Set up .env ────────────────────────────────────────────────────────────
if [ ! -f ".env" ]; then
  info "No .env found. Copying from .env.example..."
  cp .env.example .env

  # Generate strong secrets automatically
  info "Generating random secrets..."

  PG_PASS=$(openssl rand -hex 16)
  SECRET_KEY=$(openssl rand -hex 32)
  N8N_PASS=$(openssl rand -base64 12 | tr -d '/')
  N8N_ENC=$(openssl rand -base64 24 | head -c 32)
  EVOLUTION_KEY=$(openssl rand -hex 16)

  # Replace placeholders in .env (macOS + Linux compatible)
  sed -i "s|CHANGE_ME_STRONG_PASSWORD_32_CHARS_MINIMUM|${PG_PASS}|g" .env
  sed -i "s|CHANGE_ME_64_HEX_CHARS_GENERATE_WITH_OPENSSL_RAND_HEX_32|${SECRET_KEY}|g" .env
  sed -i "s|CHANGE_ME_N8N_PASSWORD|${N8N_PASS}|g" .env
  sed -i "s|CHANGE_ME_EXACTLY_32_CHARACTERS_|${N8N_ENC}|g" .env
  sed -i "s|CHANGE_ME_EVOLUTION_GLOBAL_API_KEY|${EVOLUTION_KEY}|g" .env

  echo ""
  warn "IMPORTANT: Generated secrets written to .env"
  warn "Edit .env now and set:"
  warn "  - DOMAIN (your actual domain)"
  warn "  - ACME_EMAIL (for Let's Encrypt)"
  warn "  - CHATWOOT_SMTP_* (for email notifications)"
  echo ""
  read -rp "Press ENTER after editing .env to continue (Ctrl+C to abort): "
else
  success ".env already exists, using existing configuration."
fi

# ── 4. Validate required .env vars ────────────────────────────────────────────
info "Validating .env configuration..."
source .env

[ "${DOMAIN:-}" = "yourdomain.com" ] && error "DOMAIN is still set to 'yourdomain.com'. Edit .env first."
[ "${ACME_EMAIL:-}" = "your@email.com" ] && error "ACME_EMAIL is still a placeholder. Edit .env first."
[ -z "${POSTGRES_PASSWORD:-}" ] && error "POSTGRES_PASSWORD is empty."
[ -z "${CHATWOOT_SECRET_KEY_BASE:-}" ] && error "CHATWOOT_SECRET_KEY_BASE is empty."
[ -z "${N8N_ENCRYPTION_KEY:-}" ] && error "N8N_ENCRYPTION_KEY is empty."
[ -z "${AUTHENTICATION_API_KEY:-}" ] && error "AUTHENTICATION_API_KEY is empty."

success "Configuration looks good."

# ── 5. Pull images ─────────────────────────────────────────────────────────────
info "Pulling Docker images (this may take a few minutes)..."
docker compose pull
success "Images pulled."

# ── 6. Start infrastructure ───────────────────────────────────────────────────
info "Starting PostgreSQL and Redis..."
docker compose up -d postgres redis

info "Waiting for PostgreSQL to be healthy..."
for i in $(seq 1 30); do
  if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-whatsapp}" >/dev/null 2>&1; then
    success "PostgreSQL is ready."
    break
  fi
  [ $i -eq 30 ] && error "PostgreSQL did not start in time."
  sleep 2
done

# ── 7. Run Chatwoot database migrations ───────────────────────────────────────
info "Running Chatwoot database migrations..."
docker compose run --rm chatwoot bundle exec rails db:chatwoot_prepare
success "Chatwoot database prepared."

# ── 8. Start all services ─────────────────────────────────────────────────────
info "Starting all services..."
docker compose up -d
success "All services started."

# ── 9. Print summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}  Setup Complete!${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo -e "  Chatwoot (Inbox/CRM)   ${GREEN}https://chatwoot.${DOMAIN}${NC}"
echo -e "  n8n (Automation)       ${GREEN}https://n8n.${DOMAIN}${NC}"
echo -e "  Evolution API          ${GREEN}https://evolution.${DOMAIN}${NC}"
echo -e "  Traefik Dashboard      ${GREEN}https://traefik.${DOMAIN}${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Create your admin account at https://chatwoot.${DOMAIN}"
echo "  2. Log in to n8n at https://n8n.${DOMAIN} (user: ${N8N_BASIC_AUTH_USER:-admin})"
echo "  3. Import workflows from ./workflows/ in the n8n UI"
echo "  4. Call Evolution API to create a WhatsApp instance:"
echo "     POST https://evolution.${DOMAIN}/instance/create"
echo "     Header: apikey: ${AUTHENTICATION_API_KEY}"
echo "  5. Scan the QR code at:"
echo "     GET https://evolution.${DOMAIN}/instance/connect/<instance-name>"
echo ""
echo "  See docs/SETUP.md for the full walkthrough."
echo ""
