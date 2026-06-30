-- Initialize databases for the WhatsApp stack
-- This script runs once when PostgreSQL starts for the first time.

CREATE DATABASE chatwoot;
CREATE DATABASE evolution_api;
CREATE DATABASE n8n;

-- Grant all privileges to the stack user
GRANT ALL PRIVILEGES ON DATABASE chatwoot TO whatsapp;
GRANT ALL PRIVILEGES ON DATABASE evolution_api TO whatsapp;
GRANT ALL PRIVILEGES ON DATABASE n8n TO whatsapp;
