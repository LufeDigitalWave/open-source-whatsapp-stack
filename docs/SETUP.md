# Setup Guide

## Prerequisites

- A VPS running Ubuntu 22.04 or Debian 12 (minimum 2 vCPU / 4 GB RAM)
- Docker >= 24 and Docker Compose v2 installed
- A domain with DNS managed by you (Cloudflare or similar)
- Ports 80 and 443 open on the VPS firewall

### Installing Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in for the group to take effect
```

---

## Step 1 — Clone and configure

```bash
git clone https://github.com/LufeDigitalWave/open-source-whatsapp-stack.git
cd open-source-whatsapp-stack
cp .env.example .env
nano .env   # or vim, your choice
```

Minimum values to set in `.env`:

| Variable | Example |
|---|---|
| `DOMAIN` | `mycompany.com` |
| `ACME_EMAIL` | `admin@mycompany.com` |
| `CHATWOOT_SMTP_USERNAME` | `noreply@mycompany.com` |
| `CHATWOOT_SMTP_PASSWORD` | Gmail App Password |

The setup script generates all random secrets (passwords, encryption keys) for you automatically if you leave the `CHANGE_ME_*` placeholders in place.

### DNS records required

Point these subdomains to your VPS IP **before** running the setup (Let's Encrypt needs to resolve them):

```
chatwoot.mycompany.com   A   <VPS_IP>
n8n.mycompany.com        A   <VPS_IP>
evolution.mycompany.com  A   <VPS_IP>
traefik.mycompany.com    A   <VPS_IP>
```

---

## Step 2 — Run the setup script

```bash
chmod +x setup.sh
./setup.sh
```

The script will:

1. Check that Docker is installed
2. Create the external Docker network `web` used by Traefik
3. Generate random secrets and write them to `.env`
4. Pull all Docker images
5. Start PostgreSQL and Redis first, wait for health
6. Run Chatwoot database migrations (`db:chatwoot_prepare`)
7. Start all remaining services
8. Print the URLs and next steps

The first run takes 3-5 minutes depending on your server and download speed.

---

## Step 3 — Create a Chatwoot account

1. Open `https://chatwoot.DOMAIN` in your browser
2. You will be redirected to the registration page (first user becomes super-admin)
3. Fill in your name, email, and password
4. You are now inside Chatwoot — explore the Inbox and Settings sections

---

## Step 4 — Access n8n and import workflows

1. Open `https://n8n.DOMAIN`
2. Log in with the credentials set in `.env` (`N8N_BASIC_AUTH_USER` / `N8N_BASIC_AUTH_PASSWORD`)
3. Import workflows from the `./workflows/` directory:
   - Go to **Workflows** → **Import from file**
   - Import `echo-bot.json` and/or `lead-capture.json`
4. For `lead-capture.json`, also run the schema migration against PostgreSQL:

```bash
docker compose exec -T postgres psql -U whatsapp -d n8n < workflows/leads-schema.sql
```

5. Configure the credentials required by each workflow (see below)

### Configuring n8n credentials

**Evolution API Key** (used by both workflows):
- In n8n, go to **Credentials** → **New** → **Header Auth**
- Name: `Evolution API Key`
- Header name: `apikey`
- Header value: the value of `AUTHENTICATION_API_KEY` from your `.env`

**PostgreSQL** (used by lead-capture):
- In n8n, go to **Credentials** → **New** → **Postgres**
- Host: `postgres`, Port: `5432`
- Database: `n8n`, User/Password: from your `.env`

---

## Step 5 — Create a WhatsApp instance in Evolution API

```bash
# Replace <your-apikey> with the value of AUTHENTICATION_API_KEY from .env
curl -X POST https://evolution.DOMAIN/instance/create \
  -H "Content-Type: application/json" \
  -H "apikey: <your-apikey>" \
  -d '{
    "instanceName": "mycompany",
    "qrcode": true,
    "integration": "WHATSAPP-BAILEYS"
  }'
```

You will get back a `qrcode.base64` — render it or use the next endpoint.

---

## Step 6 — Scan the QR code

Open in your browser (you will see a QR code image):

```
https://evolution.DOMAIN/instance/connect/mycompany
```

Open WhatsApp on your phone → Linked Devices → Link a Device → scan the QR code.

Wait a few seconds until the instance status becomes `open`.

---

## Step 7 — Configure the Evolution API webhook

Point Evolution API events to your n8n webhook:

```bash
curl -X POST https://evolution.DOMAIN/webhook/set/mycompany \
  -H "Content-Type: application/json" \
  -H "apikey: <your-apikey>" \
  -d '{
    "url": "https://n8n.DOMAIN/webhook/whatsapp-leads",
    "webhook_by_events": false,
    "webhook_base64": false,
    "events": ["MESSAGES_UPSERT"]
  }'
```

Change the webhook path to match whichever workflow you want to use (`whatsapp-echo` or `whatsapp-leads`).

---

## Troubleshooting

### Traefik is not issuing a certificate

- Ensure DNS propagated: `dig +short chatwoot.DOMAIN` must return your VPS IP
- Check Traefik logs: `docker compose logs -f traefik`
- Let's Encrypt rate-limits: if you triggered too many failed cert requests, wait 1 hour

### Chatwoot shows a 500 error

- Check if migrations ran: `docker compose logs chatwoot | grep -i migration`
- Re-run migrations: `docker compose run --rm chatwoot bundle exec rails db:chatwoot_prepare`

### Evolution API QR code expired

QR codes expire after ~20 seconds. If you missed it:

```bash
curl -X DELETE https://evolution.DOMAIN/instance/logout/mycompany \
  -H "apikey: <your-apikey>"
# Then reconnect
curl https://evolution.DOMAIN/instance/connect/mycompany \
  -H "apikey: <your-apikey>"
```

### n8n webhook not receiving messages

- Ensure the workflow is **Activated** (toggle in top-right of the workflow editor)
- Verify the Evolution API webhook is set: `GET https://evolution.DOMAIN/webhook/find/mycompany`
- Check n8n execution log for errors

### Check all service health

```bash
docker compose ps
docker compose logs --tail=50 <service-name>
```

---

## Updating

```bash
docker compose pull
docker compose up -d
# For Chatwoot, run migrations after each major update:
docker compose run --rm chatwoot bundle exec rails db:migrate
```
