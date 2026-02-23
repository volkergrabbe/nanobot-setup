# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

Repository: https://github.com/volkergrabbe/nanobot-setup

---

## [2.9.6] — 2026-02-23

### Fixed
- **matrix_block JSON:** Empty `matrix_block` was concatenated directly onto the closing `}` of the telegram channel block, producing invalid JSON. Fixed by initializing `matrix_block=""` and placing the `%s` placeholder correctly after the telegram block.
- **printf argument count (SC2183):** `matrix_block` printf had 7 format variables but only 6 arguments (`$MATRIX_USER_ID` for `allowFrom` was missing). Config printf had argument count mismatch (21 vs 20). Both corrected.
- **ShellCheck SC2154:** `rooms_json` was referenced before assignment — now properly initialized before use.
- **ShellCheck SC2088:** `~/.nanobot` in quoted string does not expand — replaced with `$HOME/.nanobot`.

---

## [2.9.5] — 2026-02-23

### Fixed
- **Qdrant healthcheck:** `curl` and `wget` are not available in `qdrant/qdrant:latest`. New healthcheck uses `bash /dev/tcp/127.0.0.1/6333` TCP-connect (Bash built-in, no external binary, LXC-compatible).
- **Redis healthcheck:** `CMD` format fails in Proxmox LXC with `OCI runtime exec failed`. Switched to `CMD-SHELL` with `redis-cli -h 127.0.0.1 ping` running directly in the container process.
- **Gateway healthcheck:** `localhost` → `127.0.0.1`, `start_period` increased from 30s to 45s.
- **Heredoc-in-subshell:** `select_free_model()` used `<< PYEOF` inside `$()`, causing `syntax error near unexpected token ')'` in Bash < 5.1. Python script is now written to a temp file via `mktemp`.
- **set -e abort:** API errors in `select_free_model()` caused the script to abort. `set +e` is now set locally in the function.
- **Container paths:** `emails.py`, `switch-model.sh` and cron tasks used the host path `/opt/nanobot/data/...` instead of the container path `/root/.nanobot/...`.

### Added
- `NANOBOT_CONTAINER_DIR="/root/.nanobot"` — new variable for clear separation of host and container paths.
- `vm.overcommit_memory=1` is set automatically in phase 1 (Redis AOF stability).
- Matrix/Element channel support.

---

## [2.9.0] — 2026-02-20

### Added
- Interactive model selection with live fetch from OpenRouter (`select_free_model()`)
- Nextcloud integration with semantic search via Qdrant
- Cron setup script with predefined tasks (CVE alerts, email digest, news)
- Tailscale VPN integration
- UFW + Fail2ban firewall configuration
- Systemd service for autostart after reboot
- Automatic daily backup (03:00, 7-day retention)
- `switch-model.sh` — switch model at runtime
- `emails.py` — IMAP retrieval with structured output
- `cron-setup.sh` — automatic task setup on start

### Platforms
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Proxmox LXC (privileged + unprivileged)
- Standard VPS/VM
