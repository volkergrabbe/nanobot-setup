# AGENTS.md — nanobot-setup

> OpenCode context file. Automatisch gelesen beim Start jeder Session.
> Gilt für: OpenCode, Claude Code, Codex, Gemini CLI.

Repository:   https://github.com/volkergrabbe/nanobot-setup
Upstream:     https://github.com/HKUDS/nanobot  (kein Code hier ändern)
Fork (Matrix):https://github.com/volkergrabbe/nanobot
Basis:        setup-nanobot-v2.9.5.sh  (getestet, funktioniert)
Nächste:      setup-nanobot-v3.0.0  (Sprachauswahl + Matrix)

---

## Was dieses Repo ist

Ein einziges Bash-Script das nanobot (KI-Agent) automatisiert installiert:
Docker Stack (gateway + redis + qdrant), config.json, Workspace-Dateien, Cron-Tasks,
Tailscale, UFW/Fail2ban, systemd Autostart.

Kein Sprachproblem mehr: v3.0.0 fragt die Sprache interaktiv ab.
Ein Script — eine Sprache pro Installation.

---

## Projektstruktur

```
nanobot-setup/
├── setup-nanobot.sh              # Haupt-Script (DE+EN Sprachauswahl)
├── AGENTS.md                     # Diese Datei
├── README.md
├── CHANGELOG.md
└── docs/
    └── MATRIX_SETUP.md           # Matrix-Channel Dokumentation
```

---

## Globale Variablen (Basis v2.9.5 — vollständig)

```bash
# Defaults
DEFAULT_TIMEZONE="Europe/Berlin"
DEFAULT_LOCALE="de_DE.UTF-8"
DEFAULT_IMAP_PORT=993
DEFAULT_SMTP_PORT=587
NANOBOT_MODEL="google/gemini-2.0-flash-thinking-exp:free"

# Pfade
NANOBOT_DATA_DIR="/opt/nanobot/data"      # Host-Pfad
NANOBOT_CONTAINER_DIR="/root/.nanobot"    # Container-Pfad (Volume-Mount)

# Flags
SKIP_TAILSCALE=false
USE_LOCAL_BUILD=false
RESUME_FROM=0
LOG_FILE="/var/log/nanobot-setup.log"

# Credentials (leer — werden interaktiv befüllt)
OPENROUTER_KEY="" ; NVIDIA_KEY="" ; USE_NVIDIA="n"
PERPLEXITY_KEY="" ; USE_PERPLEXITY=""
BRAVE_KEY="" ; USE_BRAVE=""
EMAIL_USER="" ; EMAIL_PASS=""
IMAP_HOST="" ; SMTP_HOST="" ; IMAP_PORT="" ; SMTP_PORT=""
TELEGRAM_TOKEN="" ; TELEGRAM_USER_ID=""

# Onboarding
ONBOARD_NAME="" ; ONBOARD_CITY="" ; ONBOARD_TG_NAME=""
ONBOARD_HOMELAB="" ; ONBOARD_INTERESTS="" ; ONBOARD_LANG="Deutsch"
ONBOARD_BOT_NAME="" ; ONBOARD_STYLE="" ; ONBOARD_STYLE_SHORT=""
ONBOARD_PROACTIVE_TEXT=""

# Nextcloud
USE_NEXTCLOUD="n"
NC_URL="" ; NC_USER="" ; NC_PASS=""
NC_FOLDERS=()

# Matrix (NEU — noch nicht implementiert)
USE_MATRIX="n"
MATRIX_HOMESERVER="" ; MATRIX_USER_ID="" ; MATRIX_TOKEN=""
MATRIX_ROOM_POLICY="mention" ; MATRIX_ALLOW_ROOMS="" ; MATRIX_E2EE="n"
NANOBOT_IMAGE_UPSTREAM="ghcr.io/hkuds/nanobot:latest"
NANOBOT_IMAGE_FORK="ghcr.io/volkergrabbe/nanobot:matrix"
NANOBOT_IMAGE=""

# Sprache (NEU — noch nicht implementiert)
SETUP_LANG="de"   # de | en
```

---

## Ausführungsreihenfolge

```
main()
  select_setup_language()       NEU Phase 0a: de/en Auswahl
  collect_credentials()         Phase 0b: API Keys, E-Mail, Telegram, Matrix (optional)
    select_free_model()           OpenRouter Modellliste live
    select_nvidia_model()         optional NVIDIA NIM
  collect_onboarding()          Phase 0c: Name, Stadt, Bot-Persönlichkeit
  collect_nextcloud()           Phase 0d: Nextcloud/Qdrant (optional)
  phase1_system()               apt-get, timezone, vm.overcommit_memory=1
  phase2_docker()               Docker CE + Compose plugin
  phase3_data_dir()             /opt/nanobot/data/ + Symlink /root/.nanobot
  phase3b_build_sync_image()    nanobot-sync:local (nur Nextcloud)
  phase4_nanobot_config()       config.json (chmod 600)
  phase5_topics()               SOUL.md, USER.md, AGENTS.md, MEMORY.md,
                                emails.py, switch-model.sh, cron-setup.sh,
                                nextcloud-sync.sh (nur Nextcloud)
  phase6_docker_compose()       docker-compose.yml (dynamisch: Image + ENV)
  phase7_tailscale()            Tailscale VPN (--skip-ts zum Überspringen)
  phase8_security()             UFW + Fail2ban
  phase9_autostart()            systemd + Backup-Cron
  phase10_start()               docker compose up -d + cron-setup.sh
  show_summary()                Secrets unset + Zusammenfassung
```

CLI-Flags: --skip-ts   --resume-from N  (N = 1..10)

---

## Pfad-Regel (kritisch!)

```bash
# HOST-Shell / Setup-Script:     NANOBOT_DATA_DIR
# Container-Intern (emails.py,
# switch-model.sh, cron-tasks):  NANOBOT_CONTAINER_DIR

# Volume-Mapping in docker-compose.yml:
# ${NANOBOT_DATA_DIR}  ->  /root/.nanobot  (NANOBOT_CONTAINER_DIR)

# RICHTIG: emails.py  CONFIG_FILE = '/root/.nanobot/config.json'
# FALSCH:  emails.py  CONFIG_FILE = '/opt/nanobot/data/config.json'
```

---

## Ausstehende Implementierungen (priorisiert)

### #1 — HOCH: Sprachauswahl (select_setup_language)

Neue Funktion am Scriptanfang, vor collect_credentials():

```bash
select_setup_language() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║  Nanobot Setup — Sprache / Language  ║"
    echo "╠══════════════════════════════════════╣"
    echo "║  1) Deutsch                          ║"
    echo "║  2) English                          ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    read -p " Auswahl / Choice [1]: " _lang
    case "${_lang:-1}" in
        2) SETUP_LANG="en" ;;
        *) SETUP_LANG="de" ;;
    esac
}
```

Alle danach folgenden Prompts und log_*-Ausgaben müssen die Sprache auswerten:

```bash
# Hilfsfunktion — gibt DE oder EN Text zurück:
t() {
    local de="$1" en="$2"
    [[ "$SETUP_LANG" == "en" ]] && echo "$en" || echo "$de"
}

# Verwendung in Prompts:
read -p " $(t "E-Mail-Adresse" "Email address"): " EMAIL_USER
```

### #2 — HOCH: Matrix-Integration (collect_credentials + phase4 + phase6)

**A) collect_credentials() — nach Telegram-Block:**
```bash
echo ""
read -p " $(t "Matrix Channel verwenden?" "Use Matrix channel?") (j/n | y/n): " USE_MATRIX
if [[ "$USE_MATRIX" =~ ^[JjYy]$ ]]; then
    while true; do
        read -p " $(t "Homeserver URL" "Homeserver URL") (https://matrix.example.com): " MATRIX_HOMESERVER
        [[ "$MATRIX_HOMESERVER" =~ ^https?:// ]] && break
        echo " $(t "Muss mit https:// beginnen!" "Must start with https://")"
    done
    read -p " $(t "Matrix User-ID" "Matrix User-ID") (@bot:example.com): " MATRIX_USER_ID
    [[ -z "$MATRIX_USER_ID" ]] && log_error "$(t "Matrix User-ID leer!" "Matrix User-ID empty!")"
    read_secret "$(t "Matrix Access Token (syt_...)" "Matrix Access Token (syt_...)")" MATRIX_TOKEN
    read -p " Room Policy [mention/open/dm] (ENTER=mention): " _rp
    MATRIX_ROOM_POLICY="${_rp:-mention}"
    read -p " $(t "Erlaubte Räume (kommagetrennt, ENTER=alle)" "Allowed rooms (comma-separated, ENTER=all)"): " MATRIX_ALLOW_ROOMS
    read -p " $(t "E2EE aktivieren? experimental" "Enable E2EE? experimental") (j/n | y/n) [n]: " _e2ee
    MATRIX_E2EE="${_e2ee:-n}"
fi
```

**B) phase4_nanobot_config() — Matrix-Block in channels:**
```bash
local matrix_block=""
if [[ "$USE_MATRIX" =~ ^[JjYy]$ ]]; then
    local rooms_json="[]"
    if [[ -n "$MATRIX_ALLOW_ROOMS" ]]; then
        local _py_tmp; _py_tmp=$(mktemp /tmp/nanobot_XXXXXX.py)
        cat > "$_py_tmp" << 'PYEOF'
import json, sys
rooms = [r.strip() for r in sys.argv[1].split(',') if r.strip()]
print(json.dumps(rooms))
PYEOF
        rooms_json=$(python3 "$_py_tmp" "$MATRIX_ALLOW_ROOMS" 2>/dev/null) || rooms_json="[]"
        rm -f "$_py_tmp"
    fi
    local e2ee_val="false"
    [[ "$MATRIX_E2EE" =~ ^[JjYy]$ ]] && e2ee_val="true"
    matrix_block=",
    "matrix": {
      "enabled": true,
      "homeserver": "${MATRIX_HOMESERVER}",
      "user_id": "${MATRIX_USER_ID}",
      "access_token": "${MATRIX_TOKEN}",
      "roomPolicy": "${MATRIX_ROOM_POLICY}",
      "allowFrom": ["${MATRIX_USER_ID}"],
      "allowRooms": ${rooms_json},
      "e2ee": ${e2ee_val}
    }"
fi
# Einfügen: ...}%s\n' ... "$nc_block${matrix_block}"
```

**C) phase6_docker_compose() — dynamische Image-Auswahl:**
```bash
if [[ "$USE_MATRIX" =~ ^[JjYy]$ ]]; then
    NANOBOT_IMAGE="$NANOBOT_IMAGE_FORK"
    log_info "$(t "Matrix aktiv -> Fork-Image" "Matrix active -> fork image"): $NANOBOT_IMAGE"
else
    NANOBOT_IMAGE="$NANOBOT_IMAGE_UPSTREAM"
fi
# Dann: image: ${NANOBOT_IMAGE} statt hardcoded ghcr.io/hkuds/nanobot:latest
```

**D) show_summary() — Matrix Secrets unset:**
```bash
unset MATRIX_TOKEN MATRIX_HOMESERVER MATRIX_USER_ID 2>/dev/null || true
```

**E) phase5 MEMORY.md — Matrix-Sektion wenn aktiv:**
```bash
if [[ "$USE_MATRIX" =~ ^[JjYy]$ ]]; then
    matrix_memory_section="
## Matrix Channel
- Homeserver: ${MATRIX_HOMESERVER}
- User ID:    ${MATRIX_USER_ID}
- Policy:     ${MATRIX_ROOM_POLICY}
- Sync token: ${NANOBOT_CONTAINER_DIR}/matrix_sync_token
- Image:      ${NANOBOT_IMAGE_FORK}
- Einladen:   /invite ${MATRIX_USER_ID}  (in Element)"
fi
```

### #3 — MITTEL: Versioning an 7 Stellen aktualisieren

Bei v3.0.0 alle 7 Stellen:
1. # Version: 3.0.0 am Script-Anfang
2. # Änderungen v3.0.0: Block
3. Setup v3.0.0 | im Banner in main()
4. NANOBOT STACK v3.0.0 in show_summary()
5. CHANGELOG.md
6. README.md
7. Script-Datei umbenennen: setup-nanobot.sh (kein Versions-Suffix nötig)

### #4 — MITTEL: show_summary() sprachabhängig ausgeben

Alle echo/printf in show_summary() mit t() wrappen.

### #5 — NIEDRIG: --help Flag aktualisieren (zeigt noch v2.9.0)

---

## Unveränderliche Regeln aus v2.9.5

### Regel 1: Kein hardcoded Wert
Jeder Pfad, Credential, URL, Model-ID muss aus einer Variable kommen.

### Regel 2: set -e / pipefail Schutz in unzuverlässigen Funktionen
```bash
my_function() {
    local old_e; [[ $- == *e* ]] && old_e=1 || old_e=0
    set +e +o pipefail
    # ... curl, API, docker ...
    [[ "$old_e" == "1" ]] && set -eo pipefail
}
```
Bereits implementiert in: select_free_model()
Noch fehlend in: select_nvidia_model() — muss nachgezogen werden

### Regel 3: Kein Heredoc in $() — immer mktemp
Bereits korrekt implementiert in: select_free_model(), select_nvidia_model(), collect_nextcloud()

### Regel 4: LXC-kompatible Docker Healthchecks — CMD-SHELL
```yaml
# Redis (bereits korrekt in v2.9.5):
test: ["CMD-SHELL", "redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null | grep -q PONG || exit 1"]
interval: 10s  timeout: 5s  retries: 5  start_period: 15s

# Qdrant (bereits korrekt in v2.9.5, bash /dev/tcp):
test: ["CMD-SHELL", "bash -c '(echo > /dev/tcp/127.0.0.1/6333) 2>/dev/null && exit 0 || exit 1'"]
interval: 20s  timeout: 10s  retries: 6  start_period: 30s

# Gateway (bereits korrekt in v2.9.5, 127.0.0.1 statt localhost):
test: ["CMD-SHELL", "curl -sf http://127.0.0.1:18790/health || exit 1"]
interval: 30s  timeout: 10s  retries: 3  start_period: 45s
```

### Regel 5: Secrets
- Eingabe nur via read_secret() (doppelt, maskiert)
- unset in show_summary() — auch MATRIX_TOKEN
- config.json immer chmod 600
- Aus Log entfernen: sed -i '/${pattern}/d' $LOG_FILE

---

## Docker Stack

```
nanobot-gateway  ghcr.io/hkuds/nanobot:latest          Port 18790
                 OR ghcr.io/volkergrabbe/nanobot:matrix (wenn USE_MATRIX=j/y)
nanobot-redis    redis:7-alpine                         intern
nanobot-qdrant   qdrant/qdrant:latest                   intern
nanobot-sync     nanobot-sync:local                     run-only (Nextcloud)

Network: nanobot-net (bridge)
Volume:  /opt/nanobot/data  ->  /root/.nanobot
```

ENV immer: TZ, REDIS_URL, QDRANT_URL, OPENROUTER_API_KEY
ENV optional: BRAVE_API_KEY, NVIDIA_API_KEY, PERPLEXITY_API_KEY

---

## Fork-Strategie (Matrix)

- volkergrabbe/nanobot = Fork von HKUDS/nanobot
- Enthält: nanobot/channels/matrix.py, MatrixConfig in schema.py
- Dependency: matrix-nio[e2e]>=0.21.0
- Sync-Token: ~/.nanobot/matrix_sync_token
- Image wird gebaut via .github/workflows/docker-publish.yml -> ghcr.io/volkergrabbe/nanobot:matrix
- Fork bleibt bestehen solange der PR zu HKUDS/nanobot offen ist
- Wenn PR gemerged: NANOBOT_IMAGE_FORK -> NANOBOT_IMAGE_UPSTREAM wechseln

---

## Dev-Befehle

```bash
bash -n setup-nanobot.sh                           # Syntax-Check
shellcheck -e SC2034,SC2086,SC1091,SC2016 setup-nanobot.sh
sudo bash setup-nanobot.sh --resume-from 4         # Ab Phase 4 testen
cd /opt/nanobot && docker compose ps               # Stack-Status
docker inspect nanobot-gateway --format='{{json .State.Health}}' | python3 -m json.tool
docker exec -it nanobot-gateway nanobot agent -m 'wer bist du?'
rm /opt/nanobot/data/matrix_sync_token             # Matrix Sync zurücksetzen
```

---

## Plattform-Support

| Plattform | Status |
|-----------|--------|
| Ubuntu 22.04 LTS | Primär, vollständig getestet |
| Ubuntu 24.04 LTS | Unterstützt |
| Proxmox LXC (privilegiert) | Vollständig unterstützt |
| Proxmox LXC (unprivilegiert) | Benötigt lxc.cgroup2.devices.allow für docker.sock |
| VPS / VM | Vollständig unterstützt |
| ARM / Raspberry Pi | Nicht getestet |

---

*Basis: v2.9.5 (getestet) | Ziel: v3.0.0 (Sprachauswahl + Matrix) | Stand: 2026-02-23*