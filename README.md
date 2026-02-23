# 🤖 Nanobot — Self-hosted AI Agent for your Homelab

> A fully automated setup script for [Nanobot](https://github.com/HKUDS/nanobot) — a self-hosted AI agent with Telegram interface, email integration, semantic search and automatic cron tasks.  
> Powered by [Nanobot](https://github.com/HKUDS/nanobot) by HKUDS and [OpenRouter](https://openrouter.ai).

[![Version](https://img.shields.io/badge/version-2.9.5-blue)](https://github.com/volkergrabbe/nanobot-setup/releases)
[![License](https://img.shields.io/badge/license-MIT-green)](https://github.com/volkergrabbe/nanobot-setup/blob/main/LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%2022.04%2F24.04-orange)](docs/setup.md)
[![ShellCheck](https://img.shields.io/github/actions/workflow/status/volkergrabbe/nanobot-setup/shellcheck.yml?label=shellcheck)](https://github.com/volkergrabbe/nanobot-setup/actions)

---

## What this is

[Nanobot](https://github.com/HKUDS/nanobot) is an impressive open-source AI agent framework by HKUDS. This repo provides a **single setup script** that automatically configures the complete stack — including **Redis** for long-term memory and **Qdrant** for semantic vector search — on your own server, without any manual configuration.

---

## ✨ Features

- 🧠 **Free AI models** via OpenRouter (Gemini, DeepSeek, LLaMA, and more)
- 📱 **Telegram interface** — chat with your agent like a personal assistant
- 📧 **Email integration** — IMAP retrieval, summaries, priority filtering
- 🔍 **Semantic search** — index Nextcloud/Obsidian vaults via Qdrant
- ⏰ **Automatic cron tasks** — CVE alerts, news digests, daily summaries
- 🔄 **Model switching** via Telegram command at runtime
- 🏠 **100% self-hosted** — no cloud dependency, no data leaves your server
- 🐳 **Docker stack** — 3 containers, runs on Proxmox LXC, VM or VPS
- 🔒 **Secure** — UFW, Fail2ban, Tailscale integration, chmod 600 for secrets

---

## 🖥️ Requirements

| What | Requirement |
|------|-------------|
| **OS** | Ubuntu 22.04 or 24.04 (LXC, VM, VPS, Bare Metal) |
| **RAM** | Min. 4 GB (8 GB recommended) |
| **CPU** | 2 cores (4 recommended) |
| **Disk** | 20 GB free space |
| **Privileges** | Root / sudo |

**Required accounts (all free):**
- [OpenRouter](https://openrouter.ai) — AI model provider
- Telegram Bot Token from [@BotFather](https://t.me/BotFather)
- Your Telegram User ID via [@userinfobot](https://t.me/userinfobot)
- Email account with IMAP/SMTP access

**Optional accounts:**
- [Brave Search API](https://api.search.brave.com) — web search (2,000 req/month free)
- [NVIDIA NIM](https://integrate.api.nvidia.com) — 1,000 free credits
- [Perplexity API](https://docs.perplexity.ai) — online search

---

## 🚀 Quick Start

```bash
# 1. Download the script
wget https://github.com/volkergrabbe/nanobot-setup/raw/main/setup-nanobot.sh

# 2. Make executable
chmod +x setup-nanobot.sh

# 3. Run inside tmux (recommended — survives connection drops)
tmux new -s nanobot-setup
sudo bash setup-nanobot.sh

# Reconnect if disconnected:
tmux attach -t nanobot-setup
```

**Options:**
```bash
sudo bash setup-nanobot.sh --skip-ts        # Skip Tailscale
sudo bash setup-nanobot.sh --resume-from 4  # Resume from phase 4
```

The script runs fully interactive — **no hardcoded values**, everything is prompted.

---

## 📁 Repository Structure

```
nanobot-setup/
├── setup-nanobot.sh               # Setup script (bilingual DE/EN)
├── README.md                      # This file
├── CHANGELOG.md                   # Version history
├── CONTRIBUTING.md                # Contribution guidelines
├── LICENSE                        # MIT License
├── SECURITY.md                    # Security notes
├── AGENTS.md                      # AI agent configuration guide
└── docs/
    ├── setup.md                   # Full setup documentation
    └── telegram-commands.md       # All Telegram commands
```

---

## 🐳 Docker Stack

After setup, the following containers are running:

| Container | Image | Function | Port |
|-----------|-------|----------|------|
| `nanobot-gateway` | `nanobot:local` | AI Agent | 18790 (Tailscale only) |
| `nanobot-redis` | `redis:7-alpine` | Long-term memory | internal |
| `nanobot-qdrant` | `qdrant/qdrant:latest` | Semantic search | internal |

---

## 💬 Telegram Commands (Examples)

```
read my emails                            → IMAP retrieval of last 20 emails
who are you?                              → Agent introduces itself
show all cron jobs                        → Overview of automatic tasks
search OpenAI news today                  → Web search via Brave Search
any critical CVEs?                        → Security check (CVSS ≥ 9.0)
switch to deepseek/deepseek-r1:free       → Switch model
synchronize my Nextcloud                  → Nextcloud → Qdrant sync
search my notes: Docker Setup             → Semantic search
```

All commands: [docs/telegram-commands.md](https://github.com/volkergrabbe/nanobot-setup/blob/main/docs/telegram-commands.md)

---

## 🔧 Maintenance

```bash
# Check status
cd /opt/nanobot && docker compose ps

# Live logs
docker compose logs -f nanobot-gateway

# Switch model
docker exec -it nanobot-gateway \
    bash /root/.nanobot/workspace/switch-model.sh "deepseek/deepseek-r1:free"

# Restart stack
docker compose down && docker compose up -d

# Manual backup
/usr/local/bin/nanobot-backup.sh
```

---

## ⚠️ Platform Notes

**Proxmox LXC:** Docker `CMD` healthchecks fail inside LXC containers (`OCI runtime exec failed`). From v2.9.5, all healthchecks use `CMD-SHELL` or `bash /dev/tcp` — no `docker exec` required.

---

## 📖 Documentation

- [Full Setup Guide](https://github.com/volkergrabbe/nanobot-setup/blob/main/docs/setup.md)
- [Telegram Commands](https://github.com/volkergrabbe/nanobot-setup/blob/main/docs/telegram-commands.md)
- [Security Notes](https://github.com/volkergrabbe/nanobot-setup/blob/main/SECURITY.md)
- [Changelog](https://github.com/volkergrabbe/nanobot-setup/blob/main/CHANGELOG.md)

---

## 📄 License

MIT License — see [LICENSE](https://github.com/volkergrabbe/nanobot-setup/blob/main/LICENSE)

---

## 🙏 Credits

- [Nanobot](https://github.com/HKUDS/nanobot) by HKUDS — the underlying agent framework
- [OpenRouter](https://openrouter.ai) — free access to frontier AI models
- [Qdrant](https://qdrant.tech) — vector database for semantic search
- [Redis](https://redis.io) — in-memory store for long-term memory
