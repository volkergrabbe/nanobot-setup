# Security Notes

Repository: https://github.com/volkergrabbe/nanobot-setup

## Credentials & Secrets

- The setup script asks for all credentials **interactively** — no command-line parameters, no `.env` files
- All credentials are kept in RAM and cleared via `unset` at the end
- `config.json` is stored with `chmod 600` — readable only by root
- The setup log (`/var/log/nanobot-setup.log`) is automatically stripped of API keys

## Network Security

The script automatically configures UFW:

| Rule | Port | Source |
|------|------|--------|
| SSH | 22 | LAN (192.168.0.0/16) |
| SSH | 22 | Tailscale (100.64.0.0/10) |
| Nanobot API | 18790 | Tailscale (100.64.0.0/10) |
| Qdrant API | 6333 | Tailscale (100.64.0.0/10) |

> ⚠️ Port 18790 is only reachable via **Tailscale** by default — never expose it directly to the internet.

## Telegram Security

- The bot responds **exclusively** to messages from your configured Telegram User ID
- All other users are silently ignored
- Find your User ID via [@userinfobot](https://t.me/userinfobot)

## Responsible Disclosure

Please do **not** report security vulnerabilities as a public GitHub issue.  
Instead: create an issue with the `security` label or send a direct message.

Issues: https://github.com/volkergrabbe/nanobot-setup/issues
