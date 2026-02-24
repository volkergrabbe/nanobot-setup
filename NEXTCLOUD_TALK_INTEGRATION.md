# Nextcloud Talk Channel Integration — Complete Documentation

## 📚 Table of Contents

1. [Overview](#overview)
2. [Integration Problems & Solutions](#integration-problems--solutions)
3. [Installation & Prerequisites](#installation--prerequisites)
4. [Configuration](#configuration)
5. [Nextcloud Talk Setup](#nextcloud-talk-setup)
6. [Workspace Files](#workspace-files)
7. [Debugging & Testing](#debugging--testing)
8. [Example Configuration](#example-configuration)
9. [Troubleshooting](#troubleshooting)

---

## 📌 Overview

The Nextcloud Talk Channel integration enables the Nanobot Agent to receive and respond to messages via [Nextcloud Talk](https://nextcloud.com/apps/spreed/). This is based on the official **Talk Bot Webhook API** from Nextcloud.

### Features

- ✅ Webhook-based event processing (no persistent WebSocket connections)
- ✅ HMAC signature validation
- ✅ Configurable `roomPolicy` (open/mention)
- ✅ Whitelist for users and rooms
- ✅ Support for long messages (Chunking)
- ✅ Full integration with the Nanobot MessageBus

### Integration with setup-nanobot.sh

This setup script integrates:
1. **collect_nextcloud_talk()** - Interactive configuration (Phase 0c)
2. **nextcloud-talk-config.json** - Example configuration (Workspace)
3. **test-webhook.py** - Test script for webhooks
4. **AGENTS.md / MEMORY.md** - Documentation for the agent

---

## 🔧 Integration Problems & Solutions

### Problem 1: Variable Naming Inconsistency

**Original Issue:**
```bash
# INCORRECT - Mixed variable names
NC_TALK_BASEURL="" ; NC_TALK_BOTSECRET="" ; NC_TALK_WEBHOOKPATH=""
NC_TALK_ALLOWFROM="" ; NC_TALK_ALLOWROOMS="" ; NC_TALK_ROOMPOLICY=""
```

**Solution:**
```bash
# CORRECT - Consistent variable naming
NCT_URL="" ; NC_TALK_BOTSECRET="" ; NCT_WEBHOOKPATH=""
NCT_ALLOW_FROM=()   # Array
NCT_ALLOW_ROOMS=()   # Array
NCT_ROOM_POLICY="mention"
```

### Problem 2: Hardcoded Value in config.json

**Original Issue:**
```json
{
  "channels": {
    "nextcloud_talk": {
      "allowFrom": ["${NC_TALK_ALLOWFROM:-all}"],  // INCORRECT
      "allowRooms": ${NC_TALK_ALLOWROOMS:-[]}        // INCORRECT
    }
  }
}
```

**Solution:**
```json
{
  "channels": {
    "nextcloud_talk": {
      "allowFrom": [${from_json}],    // CORRECT - Array
      "allowRooms": [${rooms_json}]    // CORRECT - Array
    }
  }
}
```

### Problem 3: Test Script Not Integrated

**Original Issue:**
- `test-webhook.py` was created but not properly integrated into the workspace

**Solution:**
- Created `${NANOBOT_DATA_DIR}/workspace/test-webhook.py`
- Updated with proper variable references
- Added `chmod +x` for executable permissions

### Problem 4: Documentation Missing

**Original Issue:**
- No documentation about Nextcloud Talk setup in the script

**Solution:**
- Created `NEXTCLOUD_TALK_INTEGRATION.md` with complete documentation
- Added Nextcloud Talk setup instructions to AGENTS.md & MEMORY.md
- Included troubleshooting guide

---

## 📦 Installation & Prerequisites

### Prerequisites

- ✅ Nanobot Setup v3.0.0+ installed
- ✅ Nextcloud Talk App installed
- ✅ Public URL for ngrok or Reverse Proxy
- ✅ Bot Secret (min. 40 characters)

### Installation Steps

```bash
# 1. Run setup script
sudo bash setup-nanobot.sh

# 2. At Phase 0c, select Nextcloud Talk Channel (j)

# 3. Enter configuration (see next section)

# 4. After installation: Open Nextcloud Talk from webhook
#    (see "Nextcloud Talk Setup")
```

---

## ⚙️ Configuration

### Variables in the Setup Script

| Variable | Description | Default |
|----------|-------------|---------|
| `USE_NEXTCLOUD_TALK` | Enable Nextcloud Talk Channel | `n` |
| `NCT_URL` | Nextcloud URL (e.g. https://cloud.example.com) | - |
| `NC_TALK_BOTSECRET` | Bot Secret (min. 40 characters) | - |
| `NCT_WEBHOOKPATH` | Webhook URL path | `/webhook/nextcloud_talk` |
| `NCT_ALLOW_FROM[]` | Allowed Nextcloud User IDs | `[]` (all) |
| `NCT_ALLOW_ROOMS[]` | Allowed Room Tokens | `[]` (all) |
| `NCT_ROOM_POLICY` | Room policy (open/mention) | `mention` |

### config.json Structure

```json
{
  "channels": {
    "nextcloud_talk": {
      "enabled": true,
      "baseUrl": "https://cloud.example.com",
      "botSecret": "your-bot-secret-min-40-chars",
      "webhookPath": "/webhook/nextcloud_talk",
      "allowFrom": [
        "volker",
        "alice",
        "bob"
      ],
      "allowRooms": [
        "testtoken123",
        "productionroom789"
      ],
      "roomPolicy": "mention"
    }
  }
}
```

---

## 🔌 Nextcloud Talk Setup

### 1. Install Nextcloud Talk App

Secure the Nextcloud Talk app (fallback if no current version available):

```bash
wget https://github.com/nextcloud/spreed/archive/refs/heads/master.zip -O /tmp/spreed.zip
unzip /tmp/spreed.zip -d /tmp/
```

### 2. Create Bot Secret

```bash
# Secure bot secret creation (min. 40 characters)
openssl rand -base64 48

# Example: Xy8kL9mN3pQ4rS5tU6vW7xY8zA1bC2dE3fG4hI5jK6
```

### 3. Register Bot in Nextcloud

```bash
# On the Nextcloud server (in terminal):

php occ talk:bot:install \
  "Nanobot" \
  "your-bot-secret-min-40-zeichen" \
  "https://deine-domain.com/webhook/nextcloud_talk" \
  --feature webhook \
  --feature response

# Install bot in a Room (token from Element / Talk client):

php occ talk:bot:install-in-room "Nanobot" "<room-token>"
```

**IMPORTANT:**
- The `bot_secret` must be at least 40 characters long
- The `webhook_url` must be publicly accessible (ngrok, port-forward, reverse proxy)
- Use `webhook` and `response` features for full functionality

### 4. NGrok / Reverse Proxy Setup

#### Option 1: NGrok (simple)

```bash
# Install NGrok (if not already installed)
wget https://bin.equinox.io/c/bNyj1m1V4gg/ngrok-v3-stable-linux-amd64.tgz
tar xzf ngrok-v3-stable-linux-amd64.tgz
sudo mv ngrok /usr/local/bin/

# Create tunnel
ngrok http 18790

# Output: https://abc123.ngrok.io
```

#### Option 2: Reverse Proxy (production-ready)

**Nginx Example:**
```nginx
server {
    listen 443 ssl http2;
    server_name cloud.example.com;

    ssl_certificate /etc/ssl/certs/cloud.example.com.crt;
    ssl_certificate_key /etc/ssl/private/cloud.example.com.key;

    location /webhook/nextcloud_talk {
        proxy_pass http://localhost:18790/webhook/nextcloud_talk;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Webhook headers
        proxy_set_header X-Nextcloud-Talk-Random $http_x_nextcloud_talk_random;
        proxy_set_header X-Nextcloud-Talk-Signature $http_x_nextcloud_talk_signature;
    }
}
```

---

## 📁 Workspace Files

### 1. nextcloud-talk-config.json

Example configuration at `${NANOBOT_DATA_DIR}/workspace/nextcloud-talk-config.json`:

```json
{
  "channels": {
    "nextcloud_talk": {
      "enabled": true,
      "baseUrl": "https://cloud.example.com",
      "botSecret": "your-bot-secret-min-40-chars",
      "webhookPath": "/webhook/nextcloud_talk",
      "allowFrom": [
        "volker",
        "alice"
      ],
      "allowRooms": [
        "testtoken123",
        "productionroom789"
      ],
      "roomPolicy": "mention"
    }
  }
}
```

### 2. test-webhook.py

Test script for webhook endpoints:

```bash
# Start local test server
python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py

# Test external gateway server
python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py --test-external

# Use specific port
python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py --port 18791
```

### 3. AGENTS.md / MEMORY.md

Documentation for the agent:

```markdown
## Nextcloud Talk Channel
- Webhook Path: /webhook/nextcloud_talk
- Room Policy: mention
- Access: volker / testtoken123
- Test Script: python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py --port 18790
- Config File: ${NANOBOT_DATA_DIR}/workspace/nextcloud-talk-config.json
```

---

## 🔍 Debugging & Testing

### 1. Run Webhook Test Script

```bash
# Is gateway running?
cd /opt/nanobot && docker compose logs -f nanobot-gateway

# Start test script
python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py
```

### 2. Check Log Files

```bash
# Gateway logs
tail -f /var/log/nanobot-setup.log

# Docker logs
docker logs nanobot-gateway | grep nextcloud_talk
```

### 3. Healthcheck

```bash
# Gateway Health
docker inspect nanobot-gateway --format='{{json .State.Health}}' | python3 -m json.tool

# Redis Health
docker exec nanobot-redis redis-cli -h 127.0.0.1 -p 6379 ping
```

### 4. Connection Test

```bash
# Test webhook URL (curl)
curl -X POST http://localhost:18790/webhook/nextcloud_talk \
  -H "Content-Type: application/json" \
  -H "X-Nextcloud-Talk-Random: <random_value>" \
  -H "X-Nextcloud-Talk-Signature: <hmac_sha256>" \
  -d '{
    "type": "Create",
    "actor": {"type": "users", "id": "testuser1"},
    "object": {
      "type": "comment",
      "content": "Test message"
    },
    "target": {"type": "room", "id": "testtoken123"}
  }'
```

---

## 📋 Example Configuration

### Complete Setup Flow (DE/EN)

```bash
$ sudo bash setup-nanobot.sh

╔══════════════════════════════════════╗
║  Nanobot Setup — Sprache / Language  ║
╠══════════════════════════════════════╣
║  1) Deutsch                          ║
║  2) English                          ║
╚══════════════════════════════════════╝

 Auswahl [1]: 1

╔══════════════════════════════════════╗
║       NANOBOT STACK v3.0.0 – SETUP ABGESCHLOSSEN ║
╚══════════════════════════════════════╝

  Agent:  NanobotAgent für Volker aus Berlin
  Modell: google/gemini-2.0-flash-thinking-exp:free
  Provider: OpenRouter
  Sprache: Deutsch
  Nextcloud Talk: https://cloud.example.com (3 Benutzer, 2 Räume)

  Telegram-Test-Befehle:
  → 'lies meine emails'
  → 'wer bist du?'
  → 'synchronisiere meine Nextcloud'
  → 'suche in meinen Notizen: Docker Setup'

  Log:    /var/log/nanobot-setup.log
  Config: /opt/nanobot/data/config.json
```

### Nextcloud Talk Configuration

```bash
$ sudo bash setup-nanobot.sh --resume-from 0

╔══════════════════════════════════════╗
║  Phase 0c: Nextcloud Talk Channel (optional) ║
╚══════════════════════════════════════╝

  Use Nextcloud Talk Channel? (ngrok/port-forward is required) (j/n): j

  Nextcloud Talk Channel Setup

  Prerequisites:
    1. Nextcloud Talk App installed with Bot Feature enabled
    2. Public URL for ngrok or Reverse Proxy (https://your-domain.com/webhook/nextcloud_talk)
    3. Bot Secret minimum 40 characters

  Bot Secret creation in Nextcloud:
    php occ talk:bot:install \
      "Nanobot" \
      "dein-bot-secret-min-40-zeichen" \
      "https://deine-domain.com/webhook/nextcloud_talk" \
      --feature webhook \
      --feature response

  Nextcloud URL (e.g. https://cloud.example.com): https://cloud.example.com

  Create Bot Secret (min. 40 chars):
    Use openssl rand -base64 48 for secure secret:
  Bot Secret: <secured_input>

  Public Webhook URL:
    ngrok - tunnel=https://deine-domain.com
    If using reverse proxy, enter the URL (ends with /webhook/nextcloud_talk):
  Webhook URL: https://cloud.example.com/webhook/nextcloud_talk

  Allowed Nextcloud users (@bot:user@cloud.example.com):
  Comma-separated, ENTER = all
  User list: volker,alice,bob

  Allowed Nextcloud Talk rooms (Room tokens from Element):
  Comma-separated, ENTER = all
  Room list: testtoken123,productionroom789

  Room Policy:
    1) mention  ← @Bot required for response
    2) open     ← responds to all messages
  Policy [1]: 1

  CORRECT? (y/n): y

╔══════════════════════════════════════╗
║       NANOBOT STACK v3.0.0 – SETUP ABGESCHLOSSEN ║
╚══════════════════════════════════════╝

  Nextcloud Talk: https://cloud.example.com (3 Benutzer, 2 Räume)

  Log:    /var/log/nanobot-setup.log
  Config: /opt/nanobot/data/config.json
```

---

## ❓ Troubleshooting

### Problem: "401 Unauthorized" on Webhook

**Cause:** HMAC signature validation failed

**Solution:**
```bash
# 1. Check bot secret
cat ${NANOBOT_DATA_DIR}/workspace/nextcloud-talk-config.json | grep botSecret

# 2. Open ngrok tunnel
ngrok http 18790

# 3. Recalculate signature
openssl rand -base64 48  # -> Bot Secret

# 4. Run webhook test
python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py
```

### Problem: "Bot Secret too short"

**Cause:** Minimum 40 characters required

**Solution:**
```bash
# Create secure secret
openssl rand -base64 48

# Fallback: manually generate
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 48 | head -n 1
```

### Problem: "Cannot connect to Nextcloud"

**Cause:** ngrok tunnel or URL incorrect

**Solution:**
```bash
# 1. Check ngrok tunnel
ngrok http 18790

# 2. Validate URL
curl -I https://cloud.example.com

# 3. Correct webhook URL
# config.json → nextcloud_talk → webhookPath
```

### Problem: "Webhook not received"

**Cause:** Gateway not started or incorrect port

**Solution:**
```bash
# 1. Start gateway
cd /opt/nanobot && docker compose up -d

# 2. Gateway logs
docker logs nanobot-gateway -f

# 3. Check port
docker ps | grep nanobot-gateway

# 4. Healthcheck
curl http://127.0.0.1:18790/health
```

### Problem: "Message not handled"

**Cause:** Room policy or allowed rooms incorrectly configured

**Solution:**
```bash
# 1. Check room policy
cat ${NANOBOT_DATA_DIR}/config.json | grep roomPolicy

# 2. Copy communication token from Element Client
#   Right-click → Room → Copy Address

# 3. Update config.json allowRooms
# config.json → channels → nextcloud_talk → allowRooms

# 4. Restart gateway
docker compose restart nanobot-gateway
```

### Problem: Variable Naming Inconsistency

**Cause:** Mixed variable names in code

**Solution:**
```bash
# Check all references are consistent
grep "NCT_URL" setup-nanobot.sh
grep "NC_TALK_" setup-nanobot.sh

# All should use NCT_* prefix
# except:
# - NC_TALK_BOTSECRET (specific variable name)
# - NC_TALK_WEBHOOKPATH (specific variable name)
```

---

## 🔗 Resources

### Official Documentation

- [Nextcloud Talk Bot Webhook API](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/webhook.html)
- [NGrok Tunnel](https://ngrok.com/docs)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

### Repositories

- [nanobot-nextcloud-talk-channel](https://github.com/volkergrabbe/nanobot-nextcloud-talk-channel)
- [nanobot-setup](https://github.com/volkergrabbe/nanobot-setup)
- [Nextcloud Talk Bot](https://github.com/nextcloud/spreed)

### Community

- [Nextcloud Forum](https://help.nextcloud.com/c/support/installation/8)
- [Nanobot GitHub Discussions](https://github.com/volkergrabbe/nanobot/discussions)

---

## 📝 Change Log

### v3.0.0 (2026-02-24)

- ✅ New `collect_nextcloud_talk()` function (Phase 0c)
- ✅ Workspace files: `nextcloud-talk-config.json` & `test-webhook.py`
- ✅ config.json block for `nextcloud_talk` channel
- ✅ Documentation in `AGENTS.md` & `MEMORY.md`
- ✅ HMAC signature validation integrated
- ✅ Room policy (open/mention) supported
- ✅ Fixed variable naming inconsistency (NC_TALK_* → NCT_*)
- ✅ Fixed config.json array structure

### Known Issues

- None currently identified

---

## 🎯 Next Steps

1. **Test the Integration:**
   ```bash
   sudo bash setup-nanobot.sh --resume-from 0
   ```

2. **Configure Nextcloud Talk:**
   ```bash
   # Register bot in Nextcloud
   php occ talk:bot:install ...
   ```

3. **Set Up ngrok:**
   ```bash
   ngrok http 18790
   ```

4. **Test Webhook:**
   ```bash
   python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py
   ```

5. **Monitor Logs:**
   ```bash
   docker logs nanobot-gateway -f
   ```

---

*Last Updated: 2026-02-24 | Version: v3.0.0 | Author: Volker Grabbe*
