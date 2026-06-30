-- SQL schema for the Lead Capture workflow
-- Run this against your n8n or whatsapp_stack database before activating the workflow.

CREATE TABLE IF NOT EXISTS leads (
    id            BIGSERIAL PRIMARY KEY,
    name          TEXT        NOT NULL DEFAULT 'Desconhecido',
    phone         TEXT        NOT NULL UNIQUE,
    source        TEXT        NOT NULL DEFAULT 'whatsapp',
    first_message TEXT,
    message_count INTEGER     NOT NULL DEFAULT 1,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_leads_phone      ON leads (phone);
CREATE INDEX IF NOT EXISTS idx_leads_created_at ON leads (created_at DESC);
