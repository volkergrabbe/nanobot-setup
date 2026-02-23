# Contributing

Thank you for your interest! Contributions are welcome.

Repository: https://github.com/volkergrabbe/nanobot-setup

## Types of Contributions

- 🐛 **Bug fixes** — issues or pull requests
- 📖 **Documentation** — improvements, translations
- 🔧 **Features** — new integrations, tools, language support

## Workflow

1. Fork the repo: https://github.com/volkergrabbe/nanobot-setup/fork
2. Create a branch: `git checkout -b fix/my-fix`
3. Commit your changes: `git commit -m "fix: description"`
4. Push: `git push origin fix/my-fix`
5. Create a pull request: https://github.com/volkergrabbe/nanobot-setup/pulls

## Commit Conventions

```
feat:     new feature
fix:      bug fix
docs:     documentation
refactor: restructuring without functional change
chore:    build process, dependencies
```

## Script Guidelines

- **No hardcoded values** — everything must be configurable
- **Respect `set -e`** — errors in subshells must be handled explicitly
- **LXC compatibility** — healthchecks must not use `docker exec` (`CMD` format)
- **No secrets in logs or git**
- **ShellCheck clean** — run `shellcheck setup-nanobot.sh` before submitting
- **Test on:** Ubuntu 22.04 VM + Ubuntu 24.04 Proxmox LXC
