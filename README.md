# Agent Box

Zero-touch setup for my dev box. Ubuntu 24.04 on Hetzner.

## What it does

- Creates user `demiurgo` with SSH key-only access
- Hardens SSH, sets up UFW + fail2ban
- Installs: Docker, Go, Node.js, zsh + oh-my-zsh, Neovim, mosh, tmux
- Generates an SSH key and uploads it to GitHub
- Clones dotfiles and symlinks configs
- Installs coding agents: Claude Code, Codex, OpenCode

## Usage

```bash
curl -fsSL https://raw.githubusercontent.com/jnardiello/agentbox/main/setup.sh \
  | GITHUB_TOKEN=<paste-from-password-manager> bash
```

Requires a GitHub PAT with `admin:public_key` scope.

## After setup

```bash
ssh demiurgo@<server-ip>
export ANTHROPIC_API_KEY=...
export OPENAI_API_KEY=...
cd ~/projects && start building
```
