#!/bin/bash
# ============================================================================
# Nanobot KI-Agenten Setup
# Version: 2.9.5
# Änderungen v2.9.5:
#   - BUGFIX: Qdrant Healthcheck: kein wget/curl im Image → bash /dev/tcp TCP-Connect
#   - BUGFIX: Redis Healthcheck: CMD (exec) → CMD-SHELL (sh im Container, LXC-safe)
#   - BUGFIX: Gateway Healthcheck: localhost → 127.0.0.1, start_period 45s
#   - BUGFIX: Heredoc-in-Subshell select_free_model → mktemp-Ansatz
#   - BUGFIX: set +e lokal in select_free_model (API-Fehler kein Scriptabbruch)
#   - BUGFIX: Container-Pfad /root/.nanobot für emails.py, switch-model.sh, cron
#   - NEU: NANOBOT_CONTAINER_DIR Variable
#   - NEU: vm.overcommit_memory=1 in Phase 1 (Redis AOF-Stabilität)
# Änderungen v2.9.0:
#   - Nextcloud-Onboarding: URL, User, Passwort interaktiv abgefragt
#   - Nextcloud-Sync als dedizierter Docker-Container (nanobot-sync:local)
#   - Dockerfile.sync wird automatisch gebaut
#   - AGENTS.md und MEMORY.md kennen den korrekten docker run Befehl
#   - Kein einziger hardcodierter Wert — alles variabel
# Änderungen v2.8.0:
#   - ALLE API-Keys als ENV-Variablen in docker-compose.yml (BRAVE_API_KEY fix)
#   - env_block wird dynamisch je nach aktivierten Providern aufgebaut
# Änderungen v2.7.4:
#   - Interaktives Onboarding (USER.md, SOUL.md, AGENTS.md)
# ============================================================================
set -e
set -o pipefail

DEFAULT_TIMEZONE="Europe/Berlin"
DEFAULT_LOCALE="de_DE.UTF-8"
DEFAULT_IMAP_PORT=993
DEFAULT_SMTP_PORT=587
NANOBOT_MODEL="google/gemini-2.0-flash-thinking-exp:free"
NVIDIA_KEY=""
USE_NVIDIA="n"

# Onboarding
ONBOARD_NAME="" ; ONBOARD_CITY="" ; ONBOARD_TG_NAME=""
ONBOARD_HOMELAB="" ; ONBOARD_INTERESTS="" ; ONBOARD_LANG="Deutsch"
ONBOARD_BOT_NAME="" ; ONBOARD_STYLE="" ; ONBOARD_STYLE_SHORT=""
ONBOARD_PROACTIVE_TEXT=""

# Nextcloud
USE_NEXTCLOUD="n"
NC_URL="" ; NC_USER="" ; NC_PASS=""
NC_FOLDERS=()   # Array: wird interaktiv befüllt

# Sonstige Credentials
TIMEZONE="" ; LOCALE=""
IMAP_HOST="" ; SMTP_HOST="" ; IMAP_PORT="" ; SMTP_PORT=""
OPENROUTER_KEY="" ; PERPLEXITY_KEY="" ; USE_PERPLEXITY=""
BRAVE_KEY="" ; USE_BRAVE=""
EMAIL_USER="" ; EMAIL_PASS=""
TELEGRAM_TOKEN="" ; TELEGRAM_USER_ID=""
NANOBOT_DATA_DIR="/opt/nanobot/data"        # Host-Pfad
NANOBOT_CONTAINER_DIR="/root/.nanobot"          # Container-Pfad
SKIP_TAILSCALE=false ; USE_LOCAL_BUILD=false ; RESUME_FROM=0
LOG_FILE="/var/log/nanobot-setup.log"

RED='\033[0;31m' ; GREEN='\033[0;32m' ; YELLOW='\033[1;33m'
BLUE='\033[0;34m' ; CYAN='\033[0;36m' ; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
log_step()    { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"
                echo -e "${CYAN}  $1${NC}"
                echo -e "${CYAN}══════════════════════════════════════════${NC}"; }

read_secret() {
    local description="$1" varname="$2" val1 val2
    while true; do
        read -sp "  ${description}: " val1; echo
        [[ -z "$val1" ]] && echo -e "  ${RED}Darf nicht leer sein!${NC}" && continue
        read -sp "  ${description} (Bestätigung): " val2; echo
        [[ "$val1" == "$val2" ]] && { printf -v "$varname" '%s' "$val1"; break; }
        echo -e "  ${RED}Eingaben stimmen nicht überein.${NC}"
    done
}

# ============================================================================
# MODELL-AUSWAHL
# ============================================================================
select_free_model() {
    local old_e; [[ $- == *e* ]] && old_e=1 || old_e=0
    set +e +o pipefail

    log_step "Modell-Auswahl: Kostenlose OpenRouter-Modelle"
    log_info "Rufe aktuelle Modellliste von OpenRouter ab..."

    local api_response
    api_response=$(curl -sf --max-time 15 \
        -H "Authorization: Bearer ${OPENROUTER_KEY}" \
        -H "Content-Type: application/json" \
        "https://openrouter.ai/api/v1/models" 2>/dev/null)

    if [[ -z "$api_response" ]]; then
        log_warning "OpenRouter API nicht erreichbar – Fallback: ${NANOBOT_MODEL}"
        [[ "$old_e" == "1" ]] && set -eo pipefail
        return
    fi

    local _py_tmp; _py_tmp=$(mktemp /tmp/nanobot_XXXXXX.py)
    cat > "$_py_tmp" << 'PYEOF'
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
free = [(m["id"], str(m.get("context_length", 0) // 1000) + "k")
        for m in data.get("data", []) if m.get("id", "").endswith(":free")]
free.sort(key=lambda x: x[0].lower())
for i, (mid, ctx) in enumerate(free, 1):
    print(str(i) + "|" + mid + "|" + ctx)
PYEOF

    local model_list
    model_list=$(echo "$api_response" | python3 "$_py_tmp" 2>/dev/null) || true
    rm -f "$_py_tmp"

    if [[ -z "$model_list" ]]; then
        log_warning "Keine kostenlosen Modelle – Fallback: ${NANOBOT_MODEL}"
        [[ "$old_e" == "1" ]] && set -eo pipefail
        return
    fi
    local count; count=$(echo "$model_list" | wc -l | tr -d " ")
    [[ -z "$count" || "$count" -lt 1 ]] 2>/dev/null && count=1
    local count; count=$(echo "$model_list" | wc -l)
    echo ""
    echo -e "  ${CYAN}┌──────┬────────────────────────────────────────────────┬─────────┐${NC}"
    printf   "  ${CYAN}│${NC}  %-3s  ${CYAN}│${NC} %-46s ${CYAN}│${NC} %-7s ${CYAN}│${NC}\n" "Nr." "Modell-ID" "Context"
    echo -e "  ${CYAN}├──────┼────────────────────────────────────────────────┼─────────┤${NC}"
    while IFS='|' read -r idx mid ctx; do
        printf "  ${CYAN}│${NC} %4s ${CYAN}│${NC} %-46s ${CYAN}│${NC} %7s ${CYAN}│${NC}\n" "$idx" "${mid:0:46}" "$ctx"
    done <<< "$model_list"
    echo -e "  ${CYAN}└──────┴────────────────────────────────────────────────┴─────────┘${NC}"
    echo ""
    echo -e "  ${YELLOW}Empfehlung:${NC} google/gemini-2.0-flash-thinking-exp:free"
    echo ""
    local chosen=""
    while true; do
        read -p "  Nummer (1-${count}), Modell-ID direkt, oder ENTER für Empfehlung: " _choice
        [[ -z "$_choice" ]] && { log_success "Behalte Empfehlung: ${NANOBOT_MODEL}"; return; }
        [[ "$_choice" == *"/"* ]] && { chosen="$_choice"; break; }
        if [[ "$_choice" =~ ^[0-9]+$ ]] && (( _choice >= 1 && _choice <= count )); then
            chosen=$(echo "$model_list" | awk -F'|' -v n="$_choice" '$1==n{print $2}')
            [[ -n "$chosen" ]] && break
        fi
        echo -e "  ${RED}Ungültige Eingabe.${NC}"
    done
    NANOBOT_MODEL="$chosen"
    log_success "Gewähltes Modell: ${NANOBOT_MODEL}"
}

# ============================================================================
# NVIDIA NIM
# ============================================================================
select_nvidia_model() {
    log_step "NVIDIA NIM: Modell-Auswahl"
    local api_response
    api_response=$(curl -sf --max-time 15 \
        -H "Authorization: Bearer ${NVIDIA_KEY}" \
        -H "Content-Type: application/json" \
        "https://integrate.api.nvidia.com/v1/models" 2>/dev/null)
    [[ -z "$api_response" ]] && { log_warning "NVIDIA API nicht erreichbar."; USE_NVIDIA="j"; return; }
    local _py_tmp; _py_tmp=$(mktemp /tmp/nanobot_XXXXXX.py)
    cat > "$_py_tmp" << 'PYEOF'
import json, sys
data = json.load(sys.stdin)
models = sorted([m.get('id','') for m in data.get('data',[]) if m.get('id','')])
[print(f'{i}|{mid}') for i,mid in enumerate(models, 1)]
PYEOF
    local model_list
    model_list=$(echo "$api_response" | python3 "$_py_tmp" 2>/dev/null) || true
    rm -f "$_py_tmp"
    [[ -z "$model_list" ]] && { USE_NVIDIA="j"; return; }
    local count; count=$(echo "$model_list" | wc -l)
    echo ""
    while IFS='|' read -r idx mid; do
        printf "  %4s  %s\n" "$idx" "$mid"
    done <<< "$model_list"
    echo ""
    local chosen=""
    while true; do
        read -p "  Startmodell: Nummer, ID, oder ENTER für OpenRouter-Modell: " _choice
        [[ -z "$_choice" ]] && { USE_NVIDIA="j"; return; }
        [[ "$_choice" == *"/"* ]] && { chosen="$_choice"; break; }
        if [[ "$_choice" =~ ^[0-9]+$ ]] && (( _choice >= 1 && _choice <= count )); then
            chosen=$(echo "$model_list" | awk -F'|' -v n="$_choice" '$1==n{print $2}')
            [[ -n "$chosen" ]] && break
        fi
        echo -e "  ${RED}Ungültige Eingabe.${NC}"
    done
    NANOBOT_MODEL="nvidia/${chosen}"
    USE_NVIDIA="j"
    log_success "NVIDIA NIM Startmodell: ${NANOBOT_MODEL}"
}

# ============================================================================
# PHASE 0c: NEXTCLOUD ONBOARDING
# ============================================================================
collect_nextcloud() {
    log_step "Phase 0c: Nextcloud-Integration (optional)"
    echo ""
    read -p "  Nextcloud verwenden? Obsidian Vault + Dokumente indizieren (j/n): " USE_NEXTCLOUD
    [[ ! "$USE_NEXTCLOUD" =~ ^[Jj]$ ]] && { log_info "Nextcloud übersprungen."; return; }

    echo ""
    log_info "Nextcloud-Zugangsdaten"
    echo -e "  ${YELLOW}Tipp: Nutze ein App-Passwort (Nextcloud → Einstellungen → Sicherheit)${NC}"
    echo -e "  ${YELLOW}      NICHT dein Login-Passwort!${NC}"
    echo ""
    while true; do
        read -p "  Nextcloud URL (z.B. https://cloud.example.com): " NC_URL
        NC_URL="${NC_URL%/}"   # trailing slash entfernen
        [[ "$NC_URL" =~ ^https?:// ]] && break
        echo -e "  ${RED}Muss mit http:// oder https:// beginnen!${NC}"
    done
    read -p "  Nextcloud Benutzername: " NC_USER
    [[ -z "$NC_USER" ]] && log_error "Benutzername darf nicht leer sein!"
    read_secret "Nextcloud App-Passwort" NC_PASS

    echo ""
    log_info "Verbindungstest läuft..."
    local test_result
    test_result=$(curl -sf -u "${NC_USER}:${NC_PASS}" \
        "${NC_URL}/remote.php/dav/files/${NC_USER}/" \
        -X PROPFIND -H "Depth: 0" 2>&1)
    if [[ $? -ne 0 ]] || echo "$test_result" | grep -qi "Unauthorized\|403\|401"; then
        log_warning "Verbindungstest fehlgeschlagen — trotzdem fortfahren? (j/n)"
        read -p "  " _cont
        [[ ! "$_cont" =~ ^[Jj]$ ]] && { log_error "Nextcloud abgebrochen."; }
    else
        log_success "Nextcloud Verbindung OK ✓"
    fi

    echo ""
    log_info "Verfügbare Ordner auf deiner Nextcloud:"
    local folder_list
    local _py_tmp; _py_tmp=$(mktemp /tmp/nanobot_XXXXXX.py)
    cat > "$_py_tmp" << 'PYEOF'
import sys, re
content = sys.stdin.read()
paths = re.findall(r'<d:href>([^<]+)</d:href>', content)
base = f'/remote.php/dav/files/'
for p in paths:
    idx = p.find(base)
    if idx == -1: continue
    after = p[idx+len(base):]
    after = after[after.find('/')+1:] if '/' in after else ''
    if after and after != '/' and after.endswith('/'):
        print('  /' + after)
PYEOF
    folder_list=$(curl -sf -u "${NC_USER}:${NC_PASS}" \
        "${NC_URL}/remote.php/dav/files/${NC_USER}/" \
        -X PROPFIND -H "Depth: 1" 2>/dev/null | \
        python3 "$_py_tmp" 2>/dev/null || echo "  (Ordner konnten nicht abgerufen werden)")
    rm -f "$_py_tmp"

    if [[ -n "$folder_list" ]]; then
        echo "$folder_list"
    else
        echo -e "  ${YELLOW}Ordner konnten nicht automatisch abgerufen werden.${NC}"
        echo -e "  Gib die Ordner manuell ein."
    fi

    echo ""
    log_info "Welche Ordner soll der Agent überwachen und indizieren?"
    echo -e "  ${YELLOW}Format: /OrdnerName/ (mit führendem und abschließendem Slash)${NC}"
    echo -e "  ${YELLOW}ENTER ohne Eingabe = Fertig${NC}"
    echo ""
    NC_FOLDERS=()
    while true; do
        read -p "  Ordner hinzufügen (oder ENTER zum Beenden): " _folder
        [[ -z "$_folder" ]] && break
        # Slash sicherstellen
        [[ "$_folder" != /* ]]  && _folder="/$_folder"
        [[ "$_folder" != */ ]]  && _folder="$_folder/"
        NC_FOLDERS+=("$_folder")
        echo -e "  ${GREEN}✓${NC} ${_folder} hinzugefügt"
    done

    if [[ ${#NC_FOLDERS[@]} -eq 0 ]]; then
        log_warning "Keine Ordner gewählt — Nextcloud wird deaktiviert."
        USE_NEXTCLOUD="n"
        return
    fi

    echo ""
    echo -e "  ${CYAN}──── Nextcloud-Konfiguration ──────────────────────────────${NC}"
    echo -e "  URL:     ${NC_URL}"
    echo -e "  Nutzer:  ${NC_USER}"
    echo -e "  Ordner:"
    for f in "${NC_FOLDERS[@]}"; do
        echo -e "           ${GREEN}${f}${NC}"
    done
    echo -e "  ${CYAN}───────────────────────────────────────────────────────────${NC}"
    echo ""
    read -p "  Korrekt? (j/n): " _confirm
    [[ ! "$_confirm" =~ ^[Jj]$ ]] && { collect_nextcloud; return; }
    log_success "Nextcloud-Konfiguration eingelesen."
}

# ============================================================================
# PHASE 0b: AGENT ONBOARDING
# ============================================================================
collect_onboarding() {
    log_step "Phase 0b: Agent-Onboarding"
    echo ""
    echo -e "  ${CYAN}Diese Daten personalisieren deinen KI-Agenten.${NC}"
    echo ""
    log_info "Dein Nutzerprofil (USER.md)"
    echo ""
    read -p "  Dein vollständiger Name: " ONBOARD_NAME
    [[ -z "$ONBOARD_NAME" ]] && ONBOARD_NAME="Unbekannt"
    read -p "  Dein Wohnort (Stadt): " ONBOARD_CITY
    [[ -z "$ONBOARD_CITY" ]] && ONBOARD_CITY="Unbekannt"
    read -p "  Dein Telegram-Nutzername (ohne @): " ONBOARD_TG_NAME
    [[ -z "$ONBOARD_TG_NAME" ]] && ONBOARD_TG_NAME="User"
    echo ""
    echo -e "  ${YELLOW}Homelab-Beschreibung:${NC}"
    read -p "  Dein Homelab: " ONBOARD_HOMELAB
    [[ -z "$ONBOARD_HOMELAB" ]] && ONBOARD_HOMELAB="Linux Server"
    echo ""
    echo -e "  ${YELLOW}Technische Interessen (kommagetrennt):${NC}"
    read -p "  Interessen: " ONBOARD_INTERESTS
    [[ -z "$ONBOARD_INTERESTS" ]] && ONBOARD_INTERESTS="IT, Linux, KI"
    read -p "  Bevorzugte Antwortsprache [Deutsch]: " ONBOARD_LANG
    [[ -z "$ONBOARD_LANG" ]] && ONBOARD_LANG="Deutsch"
    echo ""
    log_info "Agent-Persönlichkeit (SOUL.md)"
    echo ""
    read -p "  Name des Agenten: " ONBOARD_BOT_NAME
    [[ -z "$ONBOARD_BOT_NAME" ]] && ONBOARD_BOT_NAME="NanobotAgent"
    echo ""
    echo -e "  1) Direkt & technisch ${CYAN}← empfohlen${NC}"
    echo -e "  2) Freundlich & ausführlich"
    echo -e "  3) Minimalistisch (nur Fakten)"
    read -p "  Wahl [1]: " _p
    case "${_p:-1}" in
        2) ONBOARD_STYLE="Ich bin freundlich, ausführlich und erkläre Dinge gerne im Detail."
           ONBOARD_STYLE_SHORT="freundlich, ausführlich, erklärend" ;;
        3) ONBOARD_STYLE="Ich antworte nur mit Fakten — keine Erklärungen, keine Höflichkeiten."
           ONBOARD_STYLE_SHORT="minimalistisch, nur Fakten" ;;
        *) ONBOARD_STYLE="Ich bin direkt, präzise und technisch — kein unnötiges Gerede."
           ONBOARD_STYLE_SHORT="direkt, präzise, technisch" ;;
    esac
    echo ""
    read -p "  Proaktive Alerts (CVEs, dringende Mails)? (j/n) [j]: " _pa
    [[ "${_pa:-j}" =~ ^[Jj]$ ]] \
        && ONBOARD_PROACTIVE_TEXT="Ich bin proaktiv: CVEs >= 9.0 und dringende Mails melde ich sofort per Telegram." \
        || ONBOARD_PROACTIVE_TEXT="Ich antworte nur auf direkte Anfragen."
    log_success "Onboarding-Daten eingelesen."
}

# ============================================================================
# PHASE 0: CREDENTIALS
# ============================================================================
collect_credentials() {
    log_step "Phase 0: Zugangsdaten & Konfiguration"
    echo ""; log_warning "Alle Secrets werden zweimal abgefragt und NICHT geloggt."; echo ""
    read -p "  Zeitzone  [${DEFAULT_TIMEZONE}]: " _in; TIMEZONE="${_in:-$DEFAULT_TIMEZONE}"
    read -p "  Locale    [${DEFAULT_LOCALE}]: "   _in; LOCALE="${_in:-$DEFAULT_LOCALE}"
    echo ""
    log_info "OpenRouter API Key  →  https://openrouter.ai/settings/keys"
    read_secret "OpenRouter API Key (sk-or-v1-...)" OPENROUTER_KEY
    select_free_model || log_warning "Modell-Auswahl fehlgeschlagen – Fallback: ${NANOBOT_MODEL}"
    echo ""
    read -p "  NVIDIA NIM verwenden? (j/n): " USE_NVIDIA
    [[ "$USE_NVIDIA" =~ ^[Jj]$ ]] && { read_secret "NVIDIA API Key (nvapi-...)" NVIDIA_KEY; select_nvidia_model; }
    echo ""; read -p "  Perplexity verwenden? (j/n): " USE_PERPLEXITY
    [[ "$USE_PERPLEXITY" =~ ^[Jj]$ ]] && read_secret "Perplexity API Key (pplx-...)" PERPLEXITY_KEY
    echo ""; read -p "  Brave Search verwenden? (j/n): " USE_BRAVE
    [[ "$USE_BRAVE" =~ ^[Jj]$ ]] && read_secret "Brave Search API Key" BRAVE_KEY
    echo ""
    read -p "  E-Mail-Adresse: " EMAIL_USER
    [[ -z "$EMAIL_USER" ]] && log_error "E-Mail darf nicht leer sein!"
    log_info "IMAP-Zugangsdaten"
    while true; do read -p "  IMAP Host: " IMAP_HOST; [[ -n "$IMAP_HOST" ]] && break; echo -e "  ${RED}Darf nicht leer sein!${NC}"; done
    read -p "  IMAP Port [${DEFAULT_IMAP_PORT}]: " _in; IMAP_PORT="${_in:-$DEFAULT_IMAP_PORT}"
    read -p "  SMTP Host [ENTER=${IMAP_HOST}]: " _in; SMTP_HOST="${_in:-$IMAP_HOST}"
    read -p "  SMTP Port [${DEFAULT_SMTP_PORT}]: " _in; SMTP_PORT="${_in:-$DEFAULT_SMTP_PORT}"
    read_secret "E-Mail Passwort" EMAIL_PASS
    echo ""; read_secret "Telegram Bot Token" TELEGRAM_TOKEN
    read -p "  Telegram User-ID (Zahl): " TELEGRAM_USER_ID
    [[ -z "$TELEGRAM_USER_ID" ]]            && log_error "Telegram User-ID leer!"
    [[ ! "$TELEGRAM_USER_ID" =~ ^[0-9]+$ ]] && log_error "Muss eine Zahl sein!"
    echo ""; log_success "Zugangsdaten eingelesen."
    exec > >(tee -a "$LOG_FILE") 2>&1
}

# ============================================================================
# PHASE 1-3: SYSTEM, DOCKER, DATA DIR
# ============================================================================
phase1_system() {
    [[ "$RESUME_FROM" -gt 1 ]] && { log_info "Phase 1 übersprungen."; return; }
    log_step "Phase 1: System Setup"
    [[ "$EUID" -ne 0 ]] && log_error "Als root ausführen!"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget git nano vim tmux htop jq tree \
        ca-certificates gnupg lsb-release net-tools dnsutils iputils-ping \
        ufw fail2ban cron logrotate apt-transport-https software-properties-common \
        python3 python3-pip
    timedatectl set-timezone "$TIMEZONE"
    locale-gen "$LOCALE" > /dev/null && update-locale LANG="$LOCALE"
    sysctl -w vm.overcommit_memory=1 2>/dev/null || true
    grep -q "vm.overcommit_memory" /etc/sysctl.conf 2>/dev/null || \
        echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
    log_success "Phase 1 abgeschlossen."
}

phase2_docker() {
    [[ "$RESUME_FROM" -gt 2 ]] && { log_info "Phase 2 übersprungen."; return; }
    log_step "Phase 2: Docker Setup"
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    cat > /etc/docker/daemon.json << 'EOF'
{ "log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"},"storage-driver":"overlay2","live-restore":true }
EOF
    systemctl enable docker && systemctl start docker
    docker run --rm hello-world > /dev/null 2>&1 || log_error "Docker-Test fehlgeschlagen!"
    log_success "Phase 2 abgeschlossen."
}

phase3_data_dir() {
    [[ "$RESUME_FROM" -gt 3 ]] && { log_info "Phase 3 übersprungen."; return; }
    log_step "Phase 3: Data-Verzeichnis"
    mkdir -p "${NANOBOT_DATA_DIR}"/{memory,workspace,workspace/memory,logs,skills,backups,redis,qdrant}
    mkdir -p /opt/nanobot/build
    if   [ -L /root/.nanobot ]; then log_info "~/.nanobot Symlink existiert."
    elif [ -d /root/.nanobot ]; then mv /root/.nanobot /root/.nanobot.bak; ln -s "$NANOBOT_DATA_DIR" /root/.nanobot
    else ln -s "$NANOBOT_DATA_DIR" /root/.nanobot
    fi
    chmod 750 "$NANOBOT_DATA_DIR"
    log_success "Phase 3 abgeschlossen."
}

# ============================================================================
# PHASE 3b: NEXTCLOUD SYNC IMAGE BAUEN
# ============================================================================
phase3b_build_sync_image() {
    [[ ! "$USE_NEXTCLOUD" =~ ^[Jj]$ ]] && return
    [[ "$RESUME_FROM" -gt 3 ]] && { log_info "Phase 3b übersprungen."; return; }
    log_step "Phase 3b: Nextcloud-Sync Docker-Image bauen"
    cat > /opt/nanobot/build/Dockerfile.sync << 'DOCKERFILE'
FROM python:3.12-slim
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir \
    "webdav4[requests]" \
    qdrant-client \
    "sentence-transformers>=3.0" \
    tqdm \
    pypdf \
    python-docx
WORKDIR /data
ENTRYPOINT ["python3", "/data/workspace/nextcloud-qdrant-sync.py"]
DOCKERFILE
    log_info "Baue nanobot-sync:local Image (dauert 2-3 Minuten beim ersten Mal)..."
    docker build -t nanobot-sync:local \
        -f /opt/nanobot/build/Dockerfile.sync \
        /opt/nanobot/build/ \
        && log_success "Image nanobot-sync:local gebaut ✓" \
        || log_error "Image-Build fehlgeschlagen! Logs prüfen."
}

# ============================================================================
# PHASE 4: CONFIG.JSON
# ============================================================================
phase4_nanobot_config() {
    [[ "$RESUME_FROM" -gt 4 ]] && { log_info "Phase 4 übersprungen."; return; }
    log_step "Phase 4: Nanobot config.json"

    local providers_block
    providers_block="    \"openrouter\": { \"apiKey\": \"${OPENROUTER_KEY}\" }"
    [[ "$USE_NVIDIA" =~ ^[Jj]$ ]] && [[ -n "$NVIDIA_KEY" ]] && \
        providers_block+=",\n    \"nvidia\": { \"apiKey\": \"${NVIDIA_KEY}\", \"apiBase\": \"https://integrate.api.nvidia.com/v1\" }"
    [[ "$USE_PERPLEXITY" =~ ^[Jj]$ ]] && [[ -n "$PERPLEXITY_KEY" ]] && \
        providers_block+=",\n    \"custom\": { \"apiKey\": \"${PERPLEXITY_KEY}\", \"apiBase\": \"https://api.perplexity.ai\" }"

    local tools_block
    tools_block="    \"restrictToWorkspace\": false,
    \"shell\": { \"enabled\": true },
    \"fileSystem\": { \"enabled\": true, \"workdir\": \"${NANOBOT_DATA_DIR}/workspace\" }"
    [[ "$USE_BRAVE" =~ ^[Jj]$ ]] && [[ -n "$BRAVE_KEY" ]] && \
        tools_block+=",\n    \"braveSearch\": { \"apiKey\": \"${BRAVE_KEY}\" }"

    # Nextcloud-Block in config.json
    local nc_block=""
    if [[ "$USE_NEXTCLOUD" =~ ^[Jj]$ ]]; then
        # Folder-Array als JSON-Array bauen
        local folders_json="["
        for i in "${!NC_FOLDERS[@]}"; do
            folders_json+="\"${NC_FOLDERS[$i]}\""
            [[ $i -lt $(( ${#NC_FOLDERS[@]} - 1 )) ]] && folders_json+=","
        done
        folders_json+="]"
        nc_block=",
  \"nextcloud\": {
    \"url\": \"${NC_URL}\",
    \"username\": \"${NC_USER}\",
    \"password\": \"${NC_PASS}\",
    \"watchFolders\": ${folders_json}
  }"
    fi

    printf '{
  "providers": {
    %b
  },
  "agents": {
    "defaults": {
      "model": "%s",
      "systemPrompt": "Lies beim Start IMMER zuerst: SOUL.md, USER.md, memory/MEMORY.md im Workspace %s/workspace/. Antworte auf %s, präzise. Beende JEDE Interaktion mit vollständigem Text — niemals leer antworten. E-Mails: python3 %s/workspace/emails.py. Modell wechseln: bash %s/workspace/switch-model.sh."
    }
  },
  "channels": {
    "email": {
      "enabled": true,
      "consentGranted": true,
      "imapHost": "%s",
      "imapPort": %s,
      "imapUsername": "%s",
      "imapPassword": "%s",
      "smtpHost": "%s",
      "smtpPort": %s,
      "smtpUsername": "%s",
      "smtpPassword": "%s",
      "fromAddress": "%s",
      "allowFrom": ["%s"]
    },
    "telegram": {
      "enabled": true,
      "token": "%s",
      "allowFrom": ["%s"]
    }
  },
  "gateway": { "host": "0.0.0.0", "port": 18790 },
  "tools": {
    %b
  }%s
}\n' \
        "$providers_block" \
        "$NANOBOT_MODEL" \
        "$NANOBOT_CONTAINER_DIR" "$ONBOARD_LANG" "$NANOBOT_CONTAINER_DIR" "$NANOBOT_CONTAINER_DIR" \
        "$IMAP_HOST" "$IMAP_PORT" "$EMAIL_USER" "$EMAIL_PASS" \
        "$SMTP_HOST" "$SMTP_PORT" "$EMAIL_USER" "$EMAIL_PASS" \
        "$EMAIL_USER" "$EMAIL_USER" \
        "$TELEGRAM_TOKEN" "$TELEGRAM_USER_ID" \
        "$tools_block" \
        "$nc_block" \
        > "${NANOBOT_DATA_DIR}/config.json"

    chmod 600 "${NANOBOT_DATA_DIR}/config.json"
    log_success "config.json erstellt und gesichert (chmod 600)"
    [[ "$USE_NEXTCLOUD" =~ ^[Jj]$ ]] && log_success "  └─ Nextcloud-Block in config.json ✓"
    log_success "Phase 4 abgeschlossen."
}

# ============================================================================
# PHASE 5: WORKSPACE-DATEIEN
# ============================================================================
phase5_topics() {
    [[ "$RESUME_FROM" -gt 5 ]] && { log_info "Phase 5 übersprungen."; return; }
    log_step "Phase 5: Workspace-Dateien"

    # ── Nextcloud-Abschnitte für MEMORY.md und AGENTS.md ──────────────────
    local nc_memory_section="" nc_agents_section="" nc_cron_section=""
    if [[ "$USE_NEXTCLOUD" =~ ^[Jj]$ ]]; then
        # Ordner-Liste für Doku
        local folder_list_md=""
        for f in "${NC_FOLDERS[@]}"; do
            folder_list_md+="    - ${f}\n"
        done

        nc_memory_section="
## Nextcloud → Qdrant Integration
- Sync-Script:    ${NANOBOT_DATA_DIR}/workspace/nextcloud-qdrant-sync.py
- Wrapper:        ${NANOBOT_DATA_DIR}/workspace/nextcloud-sync.sh
- Qdrant URL:     http://qdrant:6333 (internes Docker-Netz, kein API-Key!)
- Collection:     documents
- Nextcloud URL:  ${NC_URL}
- Nutzer:         ${NC_USER}
- Creds in:       ${NANOBOT_DATA_DIR}/config.json unter 'nextcloud{}'
- Indizierte Ordner:
$(echo -e "$folder_list_md")
## Shell-Befehle für Nextcloud/Qdrant
- Test:     bash ${NANOBOT_DATA_DIR}/workspace/nextcloud-sync.sh test
- Sync:     bash ${NANOBOT_DATA_DIR}/workspace/nextcloud-sync.sh sync
- Suche:    bash ${NANOBOT_DATA_DIR}/workspace/nextcloud-sync.sh search \"ANFRAGE\"
- Statistik:bash ${NANOBOT_DATA_DIR}/workspace/nextcloud-sync.sh stats
- Force:    bash ${NANOBOT_DATA_DIR}/workspace/nextcloud-sync.sh force

## WICHTIG: Config-Pfad
- RICHTIG: ${NANOBOT_DATA_DIR}/config.json
- FALSCH:  /root/.nanobot/workspace/config.json  ← EXISTIERT NICHT"

        nc_agents_section="
## Nextcloud & Semantische Suche

### Wenn gefragt: \"suche in meinen Notizen / Dokumenten\"
1. bash ${NANOBOT_DATA_DIR}/workspace/nextcloud-sync.sh search \"SUCHBEGRIFF\"
→ NICHT in /root/.nanobot suchen
→ NICHT sagen \"ich brauche Zugangsdaten\" — sie stehen in config.json

### Wenn gefragt: \"synchronisiere Nextcloud\" / \"index meine Dateien\"
1. bash ${NANOBOT_DATA_DIR}/workspace/nextcloud-sync.sh sync

### Qdrant-Verbindungstest
1. bash ${NANOBOT_DATA_DIR}/workspace/nextcloud-sync.sh test
→ Prüft: Nextcloud-Verbindung + Qdrant-Verbindung + Collection"

        nc_cron_section='
add_task "nextcloud-sync-daily" \
    "Führe bash '"${NANOBOT_DATA_DIR}"'/workspace/nextcloud-sync.sh sync aus. Zeige Ergebnis per Telegram: wie viele Dateien neu/geändert und gesamt in Qdrant." \
    "0 6 * * *"'
    fi

    # ── AGENTS.md ──────────────────────────────────────────────────────────
    cat > "${NANOBOT_DATA_DIR}/workspace/AGENTS.md" << EOF
# AGENTS.md — Betriebsanleitung für ${ONBOARD_BOT_NAME}

## Startprotokoll (JEDE Session)
1. Lies SOUL.md — deine Identität
2. Lies USER.md — dein Nutzer
3. Lies memory/MEMORY.md — Langzeiterinnerungen
4. Starte SOFORT — frage NICHT erst um Erlaubnis

## Kernregeln
- Antworte IMMER auf ${ONBOARD_LANG}, präzise und strukturiert
- Beende JEDE Interaktion mit vollständigem Text — NIEMALS leer antworten
- Einfache Fragen (Name, wer bin ich): DIREKT antworten, KEINE Tools nötig
- E-Mails: python3 ${NANOBOT_DATA_DIR}/workspace/emails.py
- Modell wechseln: bash ${NANOBOT_DATA_DIR}/workspace/switch-model.sh "<id>"
- Config liegt IMMER unter: ${NANOBOT_DATA_DIR}/config.json
${nc_agents_section}
## Cron-Jobs
- Ergebnisse IMMER per Telegram senden
- Auch ohne Neuigkeiten: Kurze Bestätigung senden
EOF

    # ── SOUL.md ────────────────────────────────────────────────────────────
    cat > "${NANOBOT_DATA_DIR}/workspace/SOUL.md" << EOF
# SOUL.md — Persönlichkeit

## Identität
Mein Name ist ${ONBOARD_BOT_NAME}.
Ich bin ein autonomer KI-Assistent im Homelab von ${ONBOARD_NAME} in ${ONBOARD_CITY}.
${ONBOARD_STYLE}

## Kommunikation
- Sprache: ${ONBOARD_LANG}
- Stil: ${ONBOARD_STYLE_SHORT}
- ${ONBOARD_PROACTIVE_TEXT}

## Was ich NICHT tue
- Nicht um Erlaubnis fragen für klare Aufgaben
- Nicht leer antworten
- Nicht über fehlende Keys lügen wenn sie konfiguriert sind
- Nicht halluzinieren — Unsicherheit klar zugeben
- Nicht nach config.json in /root/.nanobot/workspace/ suchen — FALSCH
EOF

    # ── USER.md ────────────────────────────────────────────────────────────
    cat > "${NANOBOT_DATA_DIR}/workspace/USER.md" << EOF
# USER.md — Nutzerprofil

## Person
- Name: ${ONBOARD_NAME}
- Ort: ${ONBOARD_CITY}
- Telegram: @${ONBOARD_TG_NAME} (ID: ${TELEGRAM_USER_ID})

## Homelab
${ONBOARD_HOMELAB}

## Technische Interessen
${ONBOARD_INTERESTS}

## Bevorzugter Stil
- ${ONBOARD_LANG} immer
- Direkte Antworten ohne lange Einleitungen
EOF

    # ── HEARTBEAT.md ───────────────────────────────────────────────────────
    cat > "${NANOBOT_DATA_DIR}/workspace/HEARTBEAT.md" << 'EOF'
# HEARTBEAT.md

## Alle 30 Minuten
- Prüfe memory/active-tasks.md auf offene Aufgaben
- Falls vorhanden: Bearbeiten und Ergebnis per Telegram senden
EOF

    # ── memory/MEMORY.md ───────────────────────────────────────────────────
    mkdir -p "${NANOBOT_DATA_DIR}/workspace/memory"
    cat > "${NANOBOT_DATA_DIR}/workspace/memory/MEMORY.md" << EOF
# MEMORY.md — Langzeiterinnerungen

## Setup ($(date +%Y-%m-%d))
- Agent: ${ONBOARD_BOT_NAME} für ${ONBOARD_NAME}
- Stack: /opt/nanobot/ (Docker: gateway + redis + qdrant)
- Workspace: ${NANOBOT_DATA_DIR}/workspace/
- Config: ${NANOBOT_DATA_DIR}/config.json (chmod 600)

## Tools (aktiv)
- braveSearch | shell | fileSystem (workdir: workspace)
- BRAVE_API_KEY: ENV-Variable im Container ✓
- emails.py: ${NANOBOT_DATA_DIR}/workspace/emails.py
- switch-model.sh: ${NANOBOT_DATA_DIR}/workspace/switch-model.sh
${nc_memory_section}
EOF

    # ── emails.py ──────────────────────────────────────────────────────────
    cat > "${NANOBOT_DATA_DIR}/workspace/emails.py" << PYEOF
#!/usr/bin/env python3
import imaplib, email as emaillib, sys, json
from email.header import decode_header
from pathlib import Path

CONFIG_FILE = "${NANOBOT_CONTAINER_DIR}/config.json"

def load_config():
    try:
        c = json.load(open(CONFIG_FILE))
        ch = c.get("channels", {}).get("email", {})
        return ch.get("imapHost"), int(ch.get("imapPort", 993)), \
               ch.get("imapUsername"), ch.get("imapPassword")
    except Exception as e:
        print(f"Fehler beim Lesen der config.json: {e}", file=sys.stderr); sys.exit(1)

def decode_str(s):
    if s is None: return "(kein)"
    try:
        return " ".join(t.decode(enc or "utf-8", errors="replace") if isinstance(t, bytes) else str(t)
                        for t, enc in decode_header(s))
    except: return str(s)

def get_body(msg):
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain" and \
               "attachment" not in str(part.get("Content-Disposition", "")):
                try: return part.get_payload(decode=True).decode(
                    part.get_content_charset() or "utf-8", errors="replace")[:500]
                except: return "(Lesefehler)"
    else:
        try: return msg.get_payload(decode=True).decode(
            msg.get_content_charset() or "utf-8", errors="replace")[:500]
        except: return "(Lesefehler)"
    return ""

IMAP_HOST, IMAP_PORT, EMAIL_USER, EMAIL_PASS = load_config()
MAX_MAILS = 20

try:
    M = imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT)
    M.login(EMAIL_USER, EMAIL_PASS)
    M.select("INBOX")
    _, unseen   = M.search(None, "UNSEEN")
    _, all_msgs = M.search(None, "ALL")
    unseen_ids  = unseen[0].split()
    recent_ids  = all_msgs[0].split()[-MAX_MAILS:]
    print(f"=== POSTEINGANG: {len(all_msgs[0].split())} Mails, {len(unseen_ids)} ungelesen ===\n")
    for num in reversed(recent_ids):
        _, data = M.fetch(num, "(RFC822)")
        msg = emaillib.message_from_bytes(data[0][1])
        tag = "NEU " if num in unseen_ids else "    "
        print(f"{tag}Von:     {decode_str(msg['From'])}")
        print(f"    Betreff: {decode_str(msg['Subject'])}")
        print(f"    Datum:   {msg.get('Date','?')}")
        body = get_body(msg)
        if body.strip(): print(f"    Vorschau: {body.strip().replace(chr(10),' ')[:200]}...")
        print()
    M.logout()
    print(f"=== {len(recent_ids)} Mails abgerufen ===")
except Exception as e:
    print(f"Fehler: {e}", file=sys.stderr); sys.exit(1)
PYEOF
    chmod +x "${NANOBOT_DATA_DIR}/workspace/emails.py"

    # ── switch-model.sh ────────────────────────────────────────────────────
    cat > "${NANOBOT_DATA_DIR}/workspace/switch-model.sh" << SWITCHEOF
#!/bin/bash
CONFIG="${NANOBOT_CONTAINER_DIR}/config.json"
NEW_MODEL="\${1:-}"
if [[ -z "\$NEW_MODEL" ]]; then
    echo "Aktuelles Modell: \$(python3 -c "import json; print(json.load(open('\$CONFIG'))['agents']['defaults']['model'])")"
    python3 -c "import json; [print(f'  Provider: {k}') for k in json.load(open('\$CONFIG')).get('providers',{}).keys()]"
    exit 0
fi
OLD=\$(python3 -c "import json; print(json.load(open('\$CONFIG'))['agents']['defaults']['model'])" 2>/dev/null || echo "?")
python3 -c "
import json, shutil, os
shutil.copy2('\$CONFIG', '\$CONFIG.bak')
c = json.load(open('\$CONFIG'))
c['agents']['defaults']['model'] = '\$NEW_MODEL'
json.dump(c, open('\$CONFIG','w'), indent=2)
os.chmod('\$CONFIG', 0o600)
"
echo "Gewechselt: \$OLD → \$NEW_MODEL"
cd /opt/nanobot && docker compose restart nanobot-gateway
echo "Gateway neugestartet ✓"
SWITCHEOF
    chmod +x "${NANOBOT_DATA_DIR}/workspace/switch-model.sh"

    # ── nextcloud-sync.sh — liest Creds AUS config.json ───────────────────
    if [[ "$USE_NEXTCLOUD" =~ ^[Jj]$ ]]; then
        cat > "${NANOBOT_DATA_DIR}/workspace/nextcloud-sync.sh" << NCEOF
#!/bin/bash
# nextcloud-sync.sh
# Liest alle Zugangsdaten aus config.json — nichts ist hardcodiert!
CONFIG="${NANOBOT_DATA_DIR}/config.json"
SCRIPT="${NANOBOT_DATA_DIR}/workspace/nextcloud-qdrant-sync.py"

if [[ ! -f "\$CONFIG" ]]; then
    echo "FEHLER: config.json nicht gefunden unter: \$CONFIG"
    exit 1
fi

# Zugangsdaten aus config.json lesen
NC_URL=\$(python3 -c "import json; print(json.load(open('\$CONFIG')).get('nextcloud',{}).get('url',''))" 2>/dev/null)
NC_USER=\$(python3 -c "import json; print(json.load(open('\$CONFIG')).get('nextcloud',{}).get('username',''))" 2>/dev/null)
NC_PASS=\$(python3 -c "import json; print(json.load(open('\$CONFIG')).get('nextcloud',{}).get('password',''))" 2>/dev/null)

if [[ -z "\$NC_URL" ]] || [[ -z "\$NC_USER" ]] || [[ -z "\$NC_PASS" ]]; then
    echo "FEHLER: Nextcloud-Zugangsdaten nicht in config.json gefunden!"
    echo "Erwartet: config.json → nextcloud → url / username / password"
    exit 1
fi

# Sync-Container starten
docker run --rm \
    --network nanobot-net \
    -v "${NANOBOT_DATA_DIR}:/data" \
    -e NEXTCLOUD_URL="\$NC_URL" \
    -e NEXTCLOUD_USER="\$NC_USER" \
    -e NEXTCLOUD_PASS="\$NC_PASS" \
    -e QDRANT_URL="http://qdrant:6333" \
    -e QDRANT_COLLECTION="documents" \
    nanobot-sync:local "\${1:-sync}" \${@:2}
NCEOF
        chmod +x "${NANOBOT_DATA_DIR}/workspace/nextcloud-sync.sh"
        log_success "nextcloud-sync.sh erstellt (liest Creds aus config.json)"
    fi

    # ── topics.md ──────────────────────────────────────────────────────────
    cat > "${NANOBOT_DATA_DIR}/workspace/topics.md" << EOF
# Recherche-Themen für ${ONBOARD_BOT_NAME}

## Interessen von ${ONBOARD_NAME}
${ONBOARD_INTERESTS}

## Standard-Themen
- KI: LLM-Releases, Open-Source Entwicklungen
- IT-Security: CVEs CVSS>=9.0 sofort melden
- Linux: Kernel-Updates, Docker, Proxmox
- Windows: Patch Tuesday
EOF

    # ── sources.md ─────────────────────────────────────────────────────────
    cat > "${NANOBOT_DATA_DIR}/workspace/sources.md" << 'EOF'
# Vertrauenswürdige Quellen
| Quelle | URL | Seriosität |
|--------|-----|-----------|
| Hugging Face | https://huggingface.co/blog | 9/10 |
| Arxiv CS.AI | https://arxiv.org/list/cs.AI/recent | 10/10 |
| Heise Security | https://heise.de/security/ | 9/10 |
| MITRE CVE | https://cve.mitre.org | 10/10 |
| LWN.net | https://lwn.net | 10/10 |
| MSRC Blog | https://msrc.microsoft.com/blog/ | 10/10 |
EOF

    # ── cron-setup.sh ──────────────────────────────────────────────────────
    cat > "${NANOBOT_DATA_DIR}/workspace/cron-setup.sh" << CRONEOF
#!/bin/bash
SETUP_MARKER="${NANOBOT_CONTAINER_DIR}/workspace/.cron_setup_completed"
[ -f "\$SETUP_MARKER" ] && { echo "INFO: Cron bereits eingerichtet."; exit 0; }
add_task() {
    local name="\$1" msg="\$2" sched="\$3"
    docker exec nanobot-gateway nanobot cron list 2>/dev/null | grep -q "\"\$name\"" \
        && { echo "EXISTS: \$name"; return; }
    docker exec nanobot-gateway nanobot cron add \
        --name "\$name" --message "\$msg" --cron "\$sched" \
        && echo "OK: \$name" || echo "WARN: \$name"
}
add_task "email-daily-summary"  "Führe python3 ${NANOBOT_CONTAINER_DIR}/workspace/emails.py aus. Erstelle strukturierte Zusammenfassung. Sende per Telegram." "0 8 * * *"
add_task "email-urgent-check"   "Führe python3 ${NANOBOT_CONTAINER_DIR}/workspace/emails.py aus. Prüfe auf DRINGEND/URGENT/KRITISCH. Falls gefunden: sofort per Telegram melden." "*/30 7-22 * * *"
add_task "research-daily"       "Nutze braveSearch: KI-Neuigkeiten heute, IT Security Patches heute, Linux Updates heute. Fasse 3 wichtigste Punkte pro Thema zusammen. Sende per Telegram." "0 9 * * *"
add_task "security-alert-check" "Nutze braveSearch: CVE CVSS 9.0 heute Linux Windows Docker. Falls kritisch: sofort per Telegram mit CVE-ID. Sende immer Telegram-Bestätigung." "0 */4 * * *"
${nc_cron_section}
touch "\$SETUP_MARKER"
echo "INFO: Cron-Setup abgeschlossen."
CRONEOF
    chmod +x "${NANOBOT_DATA_DIR}/workspace/cron-setup.sh"

    log_success "Alle Workspace-Dateien angelegt."
    log_success "Phase 5 abgeschlossen."
}

# ============================================================================
# PHASE 6: DOCKER COMPOSE — ENV-BLOCK DYNAMISCH
# ============================================================================
phase6_docker_compose() {
    [[ "$RESUME_FROM" -gt 6 ]] && { log_info "Phase 6 übersprungen."; return; }
    log_step "Phase 6: Docker Compose"
    mkdir -p /opt/nanobot

    local env_block
    env_block="      - TZ=${TIMEZONE}
      - REDIS_URL=redis://redis:6379/0
      - QDRANT_URL=http://qdrant:6333
      - OPENROUTER_API_KEY=${OPENROUTER_KEY}"
    [[ "$USE_BRAVE" =~ ^[Jj]$ ]]      && [[ -n "$BRAVE_KEY" ]]      && env_block+="
      - BRAVE_API_KEY=${BRAVE_KEY}"
    [[ "$USE_NVIDIA" =~ ^[Jj]$ ]]     && [[ -n "$NVIDIA_KEY" ]]     && env_block+="
      - NVIDIA_API_KEY=${NVIDIA_KEY}"
    [[ "$USE_PERPLEXITY" =~ ^[Jj]$ ]] && [[ -n "$PERPLEXITY_KEY" ]] && env_block+="
      - PERPLEXITY_API_KEY=${PERPLEXITY_KEY}"

    local image_name="ghcr.io/hkuds/nanobot:latest"
    if ! docker manifest inspect "$image_name" > /dev/null 2>&1; then
        log_warning "GHCR-Image nicht gefunden – baue lokales Image..."
        cat > /opt/nanobot/build/Dockerfile << 'DOCKERFILE'
FROM python:3.12-slim
RUN apt-get update -qq && apt-get install -y --no-install-recommends git nodejs npm curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir --upgrade pip && pip install --no-cache-dir nanobot-ai
ENTRYPOINT ["nanobot"]
DOCKERFILE
        docker build -t nanobot:local /opt/nanobot/build/
        image_name="nanobot:local"
        USE_LOCAL_BUILD=true
    fi

    cat > /opt/nanobot/docker-compose.yml << EOF
services:
  nanobot-gateway:
    image: ${image_name}
    container_name: nanobot-gateway
    restart: unless-stopped
    volumes:
      - ${NANOBOT_DATA_DIR}:/root/.nanobot
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/nanobot:/opt/nanobot
    environment:
${env_block}
    command: gateway
    ports:
      - "18790:18790"
    depends_on:
      redis:
        condition: service_healthy
      qdrant:
        condition: service_healthy
    networks:
      - nanobot-net
    healthcheck:
      # curl ist im nanobot-Image vorhanden
      test: ["CMD-SHELL", "curl -sf http://127.0.0.1:18790/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 45s

  redis:
    image: redis:7-alpine
    container_name: nanobot-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - ${NANOBOT_DATA_DIR}/redis:/data
    networks:
      - nanobot-net
    healthcheck:
      # LXC-kompatibel: CMD-SHELL startet sh direkt im Container
      test: ["CMD-SHELL", "redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null | grep -q PONG || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 15s

  qdrant:
    image: qdrant/qdrant:latest
    container_name: nanobot-qdrant
    restart: unless-stopped
    volumes:
      - ${NANOBOT_DATA_DIR}/qdrant:/qdrant/storage
    networks:
      - nanobot-net
    healthcheck:
      # LXC-kompatibel: bash /dev/tcp built-in, keine externe Binary nötig
      test: ["CMD-SHELL", "bash -c '(echo > /dev/tcp/127.0.0.1/6333) 2>/dev/null && exit 0 || exit 1'"]
      interval: 20s
      timeout: 10s
      retries: 6
      start_period: 30s

networks:
  nanobot-net:
    driver: bridge
EOF
    log_success "docker-compose.yml erstellt"
    log_success "  └─ ENV: OPENROUTER_API_KEY ✓"
    [[ "$USE_BRAVE" =~ ^[Jj]$ ]]      && log_success "  └─ ENV: BRAVE_API_KEY ✓"
    [[ "$USE_NVIDIA" =~ ^[Jj]$ ]]     && log_success "  └─ ENV: NVIDIA_API_KEY ✓"
    [[ "$USE_PERPLEXITY" =~ ^[Jj]$ ]] && log_success "  └─ ENV: PERPLEXITY_API_KEY ✓"
    log_success "Phase 6 abgeschlossen."
}

# ============================================================================
# PHASE 7: TAILSCALE
# ============================================================================
phase7_tailscale() {
    [[ "$RESUME_FROM" -gt 7 ]] && { log_info "Phase 7 übersprungen."; return; }
    $SKIP_TAILSCALE && { log_step "Phase 7: Tailscale (ÜBERSPRUNGEN)"; return; }
    log_step "Phase 7: Tailscale VPN"
    command -v tailscale &>/dev/null || { curl -fsSL https://tailscale.com/install.sh | sh > /dev/null; systemctl enable tailscaled && systemctl start tailscaled; }
    read -sp "  Tailscale Auth-Key (ENTER=überspringen): " TS_AUTH_KEY; echo
    [[ -n "$TS_AUTH_KEY" ]] && tailscale up --authkey "$TS_AUTH_KEY" --accept-routes --hostname=nanobot-agent \
        && log_success "Tailscale verbunden." || log_warning "Später: tailscale up"
    unset TS_AUTH_KEY
    log_success "Phase 7 abgeschlossen."
}

# ============================================================================
# PHASE 8: FIREWALL
# ============================================================================
phase8_security() {
    [[ "$RESUME_FROM" -gt 8 ]] && { log_info "Phase 8 übersprungen."; return; }
    log_step "Phase 8: Firewall"
    ufw default deny incoming; ufw default allow outgoing
    ufw allow from 192.168.0.0/16 to any port 22    comment "SSH LAN"
    ufw allow from 100.64.0.0/10  to any port 22    comment "SSH Tailscale"
    ufw allow from 100.64.0.0/10  to any port 18790 comment "Nanobot Tailscale"
    ufw allow from 100.64.0.0/10  to any port 6333  comment "Qdrant Tailscale"
    ufw --force enable
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
[sshd]
enabled = true
logpath = /var/log/auth.log
EOF
    systemctl restart fail2ban
    log_success "Phase 8 abgeschlossen."
}

# ============================================================================
# PHASE 9: AUTOSTART & BACKUP
# ============================================================================
phase9_autostart() {
    [[ "$RESUME_FROM" -gt 9 ]] && { log_info "Phase 9 übersprungen."; return; }
    log_step "Phase 9: Autostart & Backup"
    cat > /etc/systemd/system/nanobot.service << EOF
[Unit]
Description=Nanobot KI-Agent Stack
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/nanobot
ExecStartPre=/bin/sleep 10
ExecStartPre=/usr/bin/docker compose up -d
ExecStartPre=-/usr/bin/bash ${NANOBOT_DATA_DIR}/workspace/cron-setup.sh
ExecStart=/usr/bin/docker compose logs -f
ExecStop=/usr/bin/docker compose down
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable nanobot.service
    cat > /usr/local/bin/nanobot-backup.sh << EOF
#!/bin/bash
BD="${NANOBOT_DATA_DIR}/backups/\$(date +%Y%m%d_%H%M%S)"
mkdir -p "\$BD"
cp "${NANOBOT_DATA_DIR}/config.json" "\$BD/" && chmod 600 "\$BD/config.json" || true
cp -r "${NANOBOT_DATA_DIR}/workspace/." "\$BD/workspace/" 2>/dev/null || true
find "${NANOBOT_DATA_DIR}/backups" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
echo "\$(date): Backup nach \$BD" >> /var/log/nanobot-backup.log
EOF
    chmod +x /usr/local/bin/nanobot-backup.sh
    (crontab -l 2>/dev/null | grep -v nanobot-backup; echo "0 3 * * * /usr/local/bin/nanobot-backup.sh") | crontab -
    log_success "Phase 9 abgeschlossen."
}

# ============================================================================
# PHASE 10: STARTEN
# ============================================================================
phase10_start() {
    [[ "$RESUME_FROM" -gt 10 ]] && { log_info "Phase 10 übersprungen."; return; }
    log_step "Phase 10: Stack starten"
    cd /opt/nanobot
    $USE_LOCAL_BUILD || docker compose pull 2>/dev/null || true
    docker compose up -d
    log_info "Warte auf Stack (max 90s)..."
    for i in {1..9}; do
        sleep 10
        docker ps --filter name=nanobot-gateway --filter status=running | grep -q nanobot-gateway \
            && { log_success "Gateway läuft nach ${i}0s. ✓"; break; }
        log_info "Warte... $i/9"
    done
    bash "${NANOBOT_DATA_DIR}/workspace/cron-setup.sh" || log_warning "Cron-Setup manuell nachholen."
    log_success "Phase 10 abgeschlossen."
}

# ============================================================================
# ABSCHLUSS
# ============================================================================
show_summary() {
    unset OPENROUTER_KEY PERPLEXITY_KEY BRAVE_KEY EMAIL_PASS TELEGRAM_TOKEN NVIDIA_KEY NC_PASS 2>/dev/null || true
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       NANOBOT STACK v2.9.5 – SETUP ABGESCHLOSSEN            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}Agent:${NC}    ${ONBOARD_BOT_NAME} für ${ONBOARD_NAME} aus ${ONBOARD_CITY}"
    echo -e "  ${GREEN}Modell:${NC}   ${NANOBOT_MODEL}"
    local prov="OpenRouter"
    [[ "$USE_NVIDIA" =~ ^[Jj]$ ]] && prov="OpenRouter + NVIDIA NIM"
    echo -e "  ${GREEN}Provider:${NC} ${prov}"
    echo -e "  ${GREEN}Sprache:${NC}  ${ONBOARD_LANG}"
    [[ "$USE_NEXTCLOUD" =~ ^[Jj]$ ]] && echo -e "  ${GREEN}Nextcloud:${NC} ${NC_URL} (${#NC_FOLDERS[@]} Ordner)"
    echo ""
    echo -e "  ${YELLOW}Telegram-Test-Befehle:${NC}"
    echo "  → 'lies meine emails'"
    echo "  → 'wer bist du?'"
    [[ "$USE_NEXTCLOUD" =~ ^[Jj]$ ]] && echo "  → 'synchronisiere meine Nextcloud'"
    [[ "$USE_NEXTCLOUD" =~ ^[Jj]$ ]] && echo "  → 'suche in meinen Notizen: Docker Setup'"
    echo ""
    echo "  Log:    ${LOG_FILE}"
    echo "  Config: ${NANOBOT_DATA_DIR}/config.json"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    chmod 600 "$LOG_FILE" 2>/dev/null || true
    for p in '"apiKey"' '"imapPassword"' '"smtpPassword"' '"token"' '"password"' 'sk-or-v1-' 'nvapi-' 'pplx-'; do
        sed -i "/${p}/d" "$LOG_FILE" 2>/dev/null || true
    done
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo -e "${CYAN}"
    echo "  ███╗   ██╗ █████╗ ███╗   ██╗ ██████╗ ██████╗  ██████╗ ████████╗"
    echo "  ████╗  ██║██╔══██╗████╗  ██║██╔═══██╗██╔══██╗██╔═══██╗╚══██╔══╝"
    echo "  ██╔██╗ ██║███████║██╔██╗ ██║██║   ██║██████╔╝██║   ██║   ██║   "
    echo "  ██║╚██╗██║██╔══██║██║╚██╗██║██║   ██║██╔══██╗██║   ██║   ██║   "
    echo "  ██║ ╚████║██║  ██║██║ ╚████║╚██████╔╝██████╔╝╚██████╔╝   ██║   "
    echo "  ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═════╝  ╚═════╝   ╚═╝   "
    echo -e "${NC}"
    echo "  Setup v2.9.5 | 100% variabel — kein hardcodierter Wert"
    echo ""
    collect_credentials
    collect_onboarding
    collect_nextcloud
    phase1_system ; phase2_docker ; phase3_data_dir ; phase3b_build_sync_image
    phase4_nanobot_config ; phase5_topics ; phase6_docker_compose
    phase7_tailscale ; phase8_security ; phase9_autostart ; phase10_start
    show_summary
}

mkdir -p "$(dirname "$LOG_FILE")"
case "${1:-}" in
    --help|-h)
        echo "Nanobot Setup v2.9.0"
        echo "  --skip-ts              Tailscale überspringen"
        echo "  --resume-from <1-10>   Ab Phase fortsetzen"
        exit 0 ;;
    --skip-ts)     SKIP_TAILSCALE=true ;;
    --resume-from) [[ "${2:-}" =~ ^[0-9]+$ ]] && RESUME_FROM="$2" || log_error "Phasennummer 1-10" ;;
esac
main
