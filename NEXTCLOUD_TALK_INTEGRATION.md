# Nextcloud Talk Channel Integration — Dokumentation

## 📚 Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [Installation & Voraussetzungen](#installation--voraussetzungen)
3. [Konfiguration](#konfiguration)
4. [Nextcloud Talk Setup](#nextcloud-talk-setup)
5. [Workspace-Dateien](#workspace-dateien)
6. [Debugging & Testing](#debugging--testing)
7. [Beispielkonfiguration](#beispielkonfiguration)
8. [Problembehandlung](#problembehandlung)

---

## 📌 Übersicht

Die Nextcloud Talk Channel Integration ermöglicht es dem Nanobot Agenten, Nachrichten über [Nextcloud Talk](https://nextcloud.com/apps/spreed/) zu empfangen und zu beantworten. Dies basiert auf dem offiziellen **Talk Bot Webhook API** von Nextcloud.

### Features

- ✅ Webhook-basierte Event-Verarbeitung (keine persistenten WebSocket-Verbindungen)
- ✅ HMAC-Signatur-Validierung
- ✅ Konfigurierbare `roomPolicy` (open/mention)
- ✅ Whitelist für Benutzer und Räume
- ✅ Unterstützung für lange Nachrichten (Chunking)
- ✅ Volle Integration mit dem Nanobot MessageBus

### Integration mit setup-nanobot.sh

Dieses Setup-Script integriert:
1. **collect_nextcloud_talk()** - Interaktive Konfiguration (Phase 0c)
2. **nextcloud-talk-config.json** - Beispiel-Konfiguration (Workspace)
3. **test-webhook.py** - Test-Skript für Webhooks
4. **AGENTS.md / MEMORY.md** - Dokumentation für den Agenten

---

## 📦 Installation & Voraussetzungen

### Voraussetzungen

- ✅ Nanobot Setup v3.0.0+ installiert
- ✅ Nextcloud Talk App installiert
- ✅ Öffentliche URL für ngrok oder Reverse Proxy
- ✅ Bot Secret (min. 40 Zeichen)

### Installationsschritte

```bash
# 1. Setup-Script ausführen
sudo bash setup-nanobot.sh

# 2. Bei Phase 0c Nextcloud Talk Channel auswählen (j)

# 3. Konfigurationen eingeben (siehe nächste Sektion)

# 4. After installation: Nextcloud Talk aus Webhook öffnen
#    (siehe "Nextcloud Talk Setup")
```

---

## ⚙️ Konfiguration

### Variables im Setup-Script

| Variable | Beschreibung | Default |
|----------|-------------|---------|
| `USE_NEXTCLOUD_TALK` | Aktiviert Nextcloud Talk Channel | `n` |
| `NCT_URL` | Nextcloud URL (z.B. https://cloud.example.com) | - |
| `NC_TALK_BOTSECRET` | Bot Secret (min. 40 Zeichen) | - |
| `NCT_WEBHOOKPATH` | Webhook-URL-Pfad | `/webhook/nextcloud_talk` |
| `NCT_ALLOW_FROM[]` | Zulässige Nextcloud User IDs | `[]` (alle) |
| `NCT_ALLOW_ROOMS[]` | Zulässige Room Tokens | `[]` (alle) |
| `NCT_ROOM_POLICY` | Raum-Policy (open/mention) | `mention` |

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

---

## 🔌 Nextcloud Talk Setup

### 1. Nextcloud Talk App installieren

Sichere das Nextcloud Talk App:
```bash
# Fallback Image (falls keine aktuelle Version verfügbar)
wget https://github.com/nextcloud/spreed/archive/refs/heads/master.zip -O /tmp/spreed.zip
unzip /tmp/spreed.zip -d /tmp/
```

### 2. Bot Secret erstellen

```bash
# Sicheren Bot Secret erstellen (min. 40 Zeichen)
openssl rand -base64 48

# Beispiel: Xy8kL9mN3pQ4rS5tU6vW7xY8zA1bC2dE3fG4hI5jK6
```

### 3. Bot in Nextcloud registrieren

```bash
# Im Nextcloud Server (im Terminal):

php occ talk:bot:install \
  "Nanobot" \
  "dein-bot-secret-min-40-zeichen" \
  "https://deine-domain.com/webhook/nextcloud_talk" \
  --feature webhook \
  --feature response

# Install bot in einer Room (Token aus Element / Talk Client):

php occ talk:bot:install-in-room "Nanobot" "<room-token>"
```

**WICHTIG:**
- Der `bot_secret` muss mindestens 40 Zeichen lang sein
- Die `webhook_url` sollte öffentlich erreichbar sein (ngrok, port-forward, reverse proxy)
- Nutze `webhook` und `response` Features für volle Funktionalität

### 4. NGrok / Reverse Proxy einrichten

#### Option 1: NGrok (einfach)

```bash
# Install NGrok (falls nicht vorhanden)
wget https://bin.equinox.io/c/bNyj1m1V4gg/ngrok-v3-stable-linux-amd64.tgz
tar xzf ngrok-v3-stable-linux-amd64.tgz
sudo mv ngrok /usr/local/bin/

# Tunnel erstellen
ngrok http 18790

# Ausgabe: https://abc123.ngrok.io
```

#### Option 2: Reverse Proxy (production-ready)

**Nginx Beispiel:**
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

        # Webhook Headers
        proxy_set_header X-Nextcloud-Talk-Random $http_x_nextcloud_talk_random;
        proxy_set_header X-Nextcloud-Talk-Signature $http_x_nextcloud_talk_signature;
    }
}
```

---

## 📁 Workspace-Dateien

### 1. nextcloud-talk-config.json

Beispiel-Konfiguration unter `${NANOBOT_DATA_DIR}/workspace/nextcloud-talk-config.json`:

```json
{
  "channels": {
    "nextcloud_talk": {
      "enabled": true,
      "baseUrl": "https://cloud.example.com",
      "botSecret": "your-bot-secret-min-40-chars",
      "webhookPath": "/webhook/nextcloud_talk",
      "allowFrom": ["volker", "alice", "bob"],
      "allowRooms": ["testtoken123", "productionroom789"],
      "roomPolicy": "mention"
    }
  }
}
```

### 2. test-webhook.py

Test-Skript für Webhook-Endpunkte:

```bash
# Lokalen Test-Server starten
python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py

# Externen Gateway server testen
python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py --test-external

# Spezifischen Port nutzen
python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py --port 18791
```

### 3. AGENTS.md / MEMORY.md

Dokumentation für den Agenten:

```markdown
## Nextcloud Talk Channel
- Webhook-Pfad: /webhook/nextcloud_talk
- Raum-Policy: mention
- Zugriff: volker / testtoken123
- Test-Skript: python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py --port 18790
- Config-File: ${NANOBOT_DATA_DIR}/workspace/nextcloud-talk-config.json
```

---

## 🔍 Debugging & Testing

### 1. Webhook Test-Skript ausführen

```bash
# Gateway läuft?
cd /opt/nanobot && docker compose logs -f nanobot-gateway

# Test-Skript starten
python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py
```

### 2. Log-Dateien prüfen

```bash
# Gateway Logs
tail -f /var/log/nanobot-setup.log

# Docker Logs
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
# Webhook URL testen (curl)
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

## 📋 Beispielkonfiguration

### Vollständiger Setup-Ablauf (DE/EN)

```bash
$ sudo bash setup-nanobot.sh

╔══════════════════════════════════════╗
║  Nanobot Setup — Sprache / Language  ║
╠══════════════════════════════════════╣
║  1) Deutsch                          ║
║  2) English                          ║
╚══════════════════════════════════════╝

 Auswahl [1]: 1

╔══════════════════════════════════════════════════════════════╗
║       NANOBOT STACK v3.0.0 (Sprachauswahl) – SETUP ABGESCHLOSSEN ║
╚══════════════════════════════════════════════════════════════╝

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

### Nextcloud Talk Konfiguration

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

╔══════════════════════════════════════════════════════════════╗
║       NANOBOT STACK v3.0.0 (Sprachauswahl) – SETUP ABGESCHLOSSEN ║
╚══════════════════════════════════════════════════════════════╝

  Nextcloud Talk: https://cloud.example.com (3 Benutzer, 2 Räume)

  Log:    /var/log/nanobot-setup.log
  Config: /opt/nanobot/data/config.json
```

---

## ❓ Problembehandlung

### Problem: "401 Unauthorized" beim Webhook

**Ursache:** HMAC-Signatur-Validierung fehlgeschlagen

**Lösung:**
```bash
# 1. Bot Secret prüfen
cat ${NANOBOT_DATA_DIR}/workspace/nextcloud-talk-config.json | grep botSecret

# 2. NGrok Tunnel öffnen
ngrok http 18790

# 3. Signature neu berechnen
openssl rand -base64 48  # -> Bot Secret

# 4. Webhook Test ausführen
python3 ${NANOBOT_DATA_DIR}/workspace/test-webhook.py
```

### Problem: "Bot Secret zu kurz"

**Ursache:** Mindestens 40 Zeichen erforderlich

**Lösung:**
```bash
# Sicheren Secret erstellen
openssl rand -base64 48

# Fallback: manuell generieren
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 48 | head -n 1
```

### Problem: "Cannot connect to Nextcloud"

**Ursache:** NGrok Tunnel oder URL fehlerhaft

**Lösung:**
```bash
# 1. NGrok Tunnel checken
ngrok http 18790

# 2. URL gültig?
curl -I https://cloud.example.com

# 3. Webhook-URL korrigieren
# config.json → nextcloud_talk → webhookPath
```

### Problem: "Webhook nicht empfangen"

**Ursache:** Gateway nicht gestartet oder falscher Port

**Lösung:**
```bash
# 1. Gateway starten
cd /opt/nanobot && docker compose up -d

# 2. Gateway Logs
docker logs nanobot-gateway -f

# 3. Port checken
docker ps | grep nanobot-gateway

# 4. Healthcheck
curl http://127.0.0.1:18790/health
```

### Problem: "Message not handled"

**Ursache:** Raum-Policy oder erlaubte Rooms falsch konfiguriert

**Lösung:**
```bash
# 1. Raum-Policy checken
cat ${NANOBOT_DATA_DIR}/config.json | grep roomPolicy

# 2. Kommunikationstoken im Element Client kopieren
#   Rechtsklick → Room → Copy Address

# 3. config.json allowRooms aktualisieren
# config.json → channels → nextcloud_talk → allowRooms

# 4. Gateway neustarten
docker compose restart nanobot-gateway
```

---

## 🔗 Ressourcen

### Offizielle Dokumentation

- [Nextcloud Talk Bot Webhook API](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/webhook.html)
- [NGrok Tunnel](https://ngrok.com/docs)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

### Repositorys

- [nanobot-nextcloud-talk-channel](https://github.com/volkergrabbe/nanobot-nextcloud-talk-channel)
- [nanobot-setup](https://github.com/volkergrabbe/nanobot-setup)
- [Nextcloud Talk Bot](https://github.com/nextcloud/spreed)

### Community

- [Nextcloud Forum](https://help.nextcloud.com/c/support/installation/8)
- [Nanobot GitHub Discussions](https://github.com/volkergrabbe/nanobot/discussions)

---

## 📝 Change Log

### v3.0.0 (2026-02-24)

- ✅ Neue Funktion `collect_nextcloud_talk()` (Phase 0c)
- ✅ Workspace-Dateien: `nextcloud-talk-config.json` & `test-webhook.py`
- ✅ config.json Block für `nextcloud_talk` Channel
- ✅ Dokumentation in `AGENTS.md` & `MEMORY.md`
- ✅ HMAC-Signatur-Validierung integriert
- ✅ Raum-Policy (open/mention) unterstützt

---

*Stand: 2026-02-24 | Version: v3.0.0 | Author: Volker Grabbe*
