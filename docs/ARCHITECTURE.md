# Architecture

## Overview

This stack wires together four open-source projects into a single Docker Compose deployment. Each component has a focused responsibility; they communicate over an isolated Docker bridge network with no ports exposed to the internet except through Traefik.

```
Internet
   |
   | :80 / :443
   v
+---------------------------+
|        Traefik v3         |  Reverse proxy + automatic TLS (Let's Encrypt)
|  chatwoot.*  n8n.*        |  Routes by Host header
|  evolution.* traefik.*    |
+--+----------+----------+--+
   |          |          |
   |   (web network — TLS terminated here, HTTP inside)
   |          |          |
   v          v          v
+--------+ +------+ +----------+
|Chatwoot| |  n8n | | Evolution|
|  :3000 | | :5678| | API :8080|
+---+----+ +--+---+ +----+-----+
    |          |          |
    +----------+----------+
               |
    (internal network — no external access)
               |
       +-------+--------+
       |                |
  +----+-----+    +-----+----+
  |PostgreSQL|    |  Redis   |
  |    :5432 |    |   :6379  |
  +----------+    +----------+
```

## Component Responsibilities

### Traefik

Traefik watches the Docker socket for containers with `traefik.enable=true` labels and automatically configures:

- HTTP → HTTPS redirect on port 80
- TLS termination with Let's Encrypt certificates on port 443
- Reverse proxy routing by hostname to the correct container

All services receive plain HTTP internally. TLS is handled exclusively at the Traefik layer.

### Evolution API

Evolution API implements the WhatsApp multi-device protocol (via the Baileys library) and exposes a REST API. It:

- Maintains persistent WhatsApp sessions (stored in PostgreSQL + local volume)
- Receives incoming messages from WhatsApp and fires webhook events to any URL you configure
- Accepts API calls to send messages, media, and reactions

**Data flow — incoming message:**
```
WhatsApp servers
      |
      | WebSocket (Baileys)
      v
 Evolution API
      |
      | HTTP POST (webhook)
      v
  n8n or Chatwoot
```

### Chatwoot

Chatwoot is a multi-channel inbox and lightweight CRM. In this stack it can receive WhatsApp messages two ways:

1. **Evolution API native integration** — configure per-instance inside Evolution API settings; it forwards messages automatically into a Chatwoot inbox.
2. **n8n relay** — n8n receives the Evolution webhook and calls the Chatwoot API to create conversations.

Chatwoot runs as two containers: the Rails web server (`chatwoot`) and a Sidekiq worker (`chatwoot-worker`) that processes background jobs (emails, webhook deliveries, notifications). Both share the same image and environment variables.

### n8n

n8n is the automation layer. It exposes webhook endpoints that Evolution API can POST to, and it can call any HTTP API (Evolution, Chatwoot, external CRMs, databases).

This stack ships two starter workflows:

| Workflow | Trigger | What it does |
|---|---|---|
| `echo-bot` | POST `/webhook/whatsapp-echo` | Reads incoming text, sends it back verbatim |
| `lead-capture` | POST `/webhook/whatsapp-leads` | Extracts name + phone, upserts in PostgreSQL, sends confirmation |

n8n stores its internal data (workflow definitions, credentials, execution history) in PostgreSQL — not SQLite — so it is safe for production use.

### PostgreSQL 15

Single PostgreSQL instance hosts three databases:

| Database | Owner |
|---|---|
| `chatwoot` | Chatwoot |
| `evolution_api` | Evolution API |
| `n8n` | n8n |

The `init-db.sql` script creates all three databases when the container starts for the first time.

### Redis 7

Redis is used for:

- **Chatwoot**: Sidekiq job queues, Action Cable (real-time), caching
- **Evolution API**: Instance session cache, message deduplication

## Network Topology

Two Docker networks are used:

| Network | Type | Purpose |
|---|---|---|
| `web` | External (pre-created) | Traefik ↔ public-facing containers |
| `internal` | Internal (no host routing) | Service-to-service communication |

PostgreSQL and Redis are attached **only** to the `internal` network — they are never reachable from the internet or even from the Traefik container.

## Message Flow — Incoming WhatsApp Message to n8n Workflow

```
1. User sends WhatsApp message
         |
2. WhatsApp server delivers it to Evolution API via WebSocket
         |
3. Evolution API fires HTTP POST to n8n webhook URL
   (configured via /webhook/set/<instance>)
         |
4. n8n webhook node receives the event
         |
5. Code node extracts phone, name, message text
         |
6. (lead-capture) PostgreSQL node upserts the lead
         |
7. HTTP Request node calls Evolution API /message/sendText
         |
8. Evolution API delivers the reply to WhatsApp
         |
9. User receives confirmation message
```

## Security Notes

- All secrets (passwords, API keys, encryption keys) live in `.env` — never committed to version control
- PostgreSQL and Redis are isolated on the `internal` network
- Traefik dashboard is protected by HTTP Basic Auth
- `ENABLE_ACCOUNT_SIGNUP=false` prevents unauthorized Chatwoot account creation
- Evolution API requires an `apikey` header on every request
