#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================

# DEVBOX SETUP — Ubuntu 24.04 on Hetzner

# 

# Usage:

# curl -fsSL https://raw.githubusercontent.com/jnardiello/devbox/main/setup.sh \

# | GITHUB_TOKEN=<paste-from-password-manager> bash

# 

# Idempotent: safe to re-run.

# ==============================================================================

USERNAME=“demiurgo”
GITHUB_USER=“jnardiello”
GITHUB_EMAIL=”${GITHUB_USER}@users.noreply.github.com”
SSH_KEY_PATH=”/home/${USERNAME}/.ssh/gh_ed25519”
SWAP_SIZE=“4G”
GO_VERSION=“1.24.0”
DOTFILES_REPO=“git@github.com:${GITHUB_USER}/local-machine.git”
DOTFILES_DIR=”/home/${USERNAME}/local-machine”

# — Preflight ––––––––––––––––––––––––––––––––

if [ “$(id -u)” -ne 0 ]; then
echo “❌ Run as root”
exit 1
fi

if [ -z “${GITHUB_TOKEN:-}” ]; then
echo “❌ GITHUB_TOKEN env var required”
exit 1
fi

echo “🔧 Starting devbox setup…”

# Prevent needrestart from stealing stdin when piping via curl|bash

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# — System updates ———————————————————–

echo “📦 Updating system packages…”
apt-get update -qq
apt-get upgrade -y -qq

# — Create user –––––––––––––––––––––––––––––––

if ! id “$USERNAME” &>/dev/null; then
echo “👤 Creating user ${USERNAME}…”
useradd -m -s /bin/bash -G sudo “$USERNAME”
echo “${USERNAME} ALL=(ALL) NOPASSWD:ALL” > “/etc/sudoers.d/${USERNAME}”
chmod 440 “/etc/sudoers.d/${USERNAME}”
else
echo “👤 User ${USERNAME} already exists, skipping”
fi

# — Copy authorized_keys from root —————————————––

USER_SSH_DIR=”/home/${USERNAME}/.ssh”
mkdir -p “$USER_SSH_DIR”
if [ -f /root/.ssh/authorized_keys ]; then
cp /root/.ssh/authorized_keys “${USER_SSH_DIR}/authorized_keys”
fi
chown -R “${USERNAME}:${USERNAME}” “$USER_SSH_DIR”
chmod 700 “$USER_SSH_DIR”
chmod 600 “${USER_SSH_DIR}/authorized_keys”

# — SSH hardening ————————————————————

echo “🔒 Hardening SSH…”
SSHD_CONFIG=”/etc/ssh/sshd_config”
sed -i ‘s/^#?PermitRootLogin.*/PermitRootLogin no/’ “$SSHD_CONFIG”
sed -i ’s/^#?PasswordAuthentication.*/PasswordAuthentication no/’ “$SSHD_CONFIG”
sed -i ‘s/^#?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/’ “$SSHD_CONFIG”
sed -i ’s/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/’ “$SSHD_CONFIG”
systemctl reload sshd

# — Firewall —————————————————————–

echo “🧱 Configuring firewall…”
apt-get install -y -qq ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 60000:61000/udp  # mosh
echo “y” | ufw enable

# — Fail2ban —————————————————————–

echo “🚫 Setting up fail2ban…”
apt-get install -y -qq fail2ban
if [ ! -f /etc/fail2ban/jail.local ]; then
cat > /etc/fail2ban/jail.local <<‘EOF’
[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 3
bantime = 3600
findtime = 600
EOF
fi
systemctl enable fail2ban
systemctl restart fail2ban

# — Unattended upgrades ——————————————————

echo “🔄 Enabling unattended upgrades…”
apt-get install -y -qq unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

# — Swap ———————————————————————

if [ ! -f /swapfile ]; then
echo “💾 Creating ${SWAP_SIZE} swap…”
fallocate -l “$SWAP_SIZE” /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo “/swapfile none swap sw 0 0” >> /etc/fstab
else
echo “💾 Swap already exists, skipping”
fi

# — Essential packages —————————————————––

echo “📦 Installing essentials…”
apt-get install -y -qq   
curl   
wget   
jq   
htop   
mosh   
tmux   
build-essential   
ca-certificates   
gnupg   
unzip   
ripgrep   
fd-find

# — Zsh + Oh My Zsh –––––––––––––––––––––––––––––

echo “🐚 Installing zsh…”
apt-get install -y -qq zsh

if [ ! -d “/home/${USERNAME}/.oh-my-zsh” ]; then
echo “🐚 Installing Oh My Zsh…”
sudo -u “$USERNAME” sh -c   
‘RUNZSH=no CHSH=no sh -c “$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)”’
fi

chsh -s “$(which zsh)” “$USERNAME”

# — Neovim —————————————————————––

echo “📝 Installing Neovim…”
if ! command -v nvim &>/dev/null; then
curl -fsSL -o /tmp/nvim.tar.gz   
“https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz”
tar -C /opt -xzf /tmp/nvim.tar.gz
ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
rm /tmp/nvim.tar.gz
else
echo “📝 Neovim already installed, skipping”
fi

# — Docker —————————————————————––

echo “🐳 Installing Docker…”
if ! command -v docker &>/dev/null; then
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg –dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo   
“deb [arch=$(dpkg –print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu   
$(. /etc/os-release && echo “$VERSION_CODENAME”) stable” |   
tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker “$USERNAME”
else
echo “🐳 Docker already installed, skipping”
fi

# — Go ———————————————————————–

echo “🐹 Installing Go ${GO_VERSION}…”
if [ ! -d /usr/local/go ]; then
curl -fsSL “https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz” | tar -C /usr/local -xz
else
echo “🐹 Go already installed, skipping”
fi

# — Node.js ——————————————————————

echo “📦 Installing Node.js…”
if ! command -v node &>/dev/null; then
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y -qq nodejs
else
echo “📦 Node.js already installed, skipping”
fi

# — GitHub CLI —————————————————————

echo “🐙 Installing GitHub CLI…”
if ! command -v gh &>/dev/null; then
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg   
| dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo “deb [arch=$(dpkg –print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main” |   
tee /etc/apt/sources.list.d/github-cli-stable.list > /dev/null
apt-get update -qq
apt-get install -y -qq gh
else
echo “🐙 GitHub CLI already installed, skipping”
fi

# — Git config —————————————————————

echo “⚙️ Configuring git…”
sudo -u “$USERNAME” git config –global user.name “$GITHUB_USER”
sudo -u “$USERNAME” git config –global user.email “$GITHUB_EMAIL”
sudo -u “$USERNAME” git config –global init.defaultBranch main
sudo -u “$USERNAME” git config –global core.editor nvim

# — SSH key for GitHub —————————————————––

if [ ! -f “$SSH_KEY_PATH” ]; then
echo “🔑 Generating SSH key for GitHub…”
sudo -u “$USERNAME” ssh-keygen -t ed25519 -C “devbox-$(hostname)” -f “$SSH_KEY_PATH” -N “”

echo “🔑 Uploading SSH key to GitHub…”
echo “$GITHUB_TOKEN” | sudo -u “$USERNAME” gh auth login –with-token
sudo -u “$USERNAME” gh ssh-key add “${SSH_KEY_PATH}.pub” –title “devbox-$(hostname)”
sudo -u “$USERNAME” gh auth logout –hostname github.com 2>/dev/null || true

cat > “${USER_SSH_DIR}/config” <<EOF
Host github.com
IdentityFile ${SSH_KEY_PATH}
IdentitiesOnly yes
StrictHostKeyChecking accept-new
EOF
chown “${USERNAME}:${USERNAME}” “${USER_SSH_DIR}/config”
chmod 600 “${USER_SSH_DIR}/config”
else
echo “🔑 GitHub SSH key already exists, skipping”
fi

# — Dotfiles —————————————————————–

echo “📂 Setting up dotfiles…”
if [ ! -d “$DOTFILES_DIR” ]; then
sudo -u “$USERNAME” git clone “$DOTFILES_REPO” “$DOTFILES_DIR”
else
echo “📂 Dotfiles repo already cloned, pulling latest…”
sudo -u “$USERNAME” git -C “$DOTFILES_DIR” pull || true
fi

# Symlink nvim config

sudo -u “$USERNAME” mkdir -p “/home/${USERNAME}/.config”
ln -sfn “${DOTFILES_DIR}/dotfiles/nvim” “/home/${USERNAME}/.config/nvim”

# Symlink tmux config

ln -sf “${DOTFILES_DIR}/dotfiles/tmux/tmux.conf” “/home/${USERNAME}/.tmux.conf”

# Symlink zsh config (overwrite oh-my-zsh default)

ln -sf “${DOTFILES_DIR}/dotfiles/zsh/zshrc” “/home/${USERNAME}/.zshrc”

# Symlink git config

ln -sf “${DOTFILES_DIR}/dotfiles/git/gitconfig” “/home/${USERNAME}/.gitconfig”
ln -sf “${DOTFILES_DIR}/dotfiles/git/gitignore_global” “/home/${USERNAME}/.gitignore_global”

chown -h “${USERNAME}:${USERNAME}”   
“/home/${USERNAME}/.config/nvim”   
“/home/${USERNAME}/.tmux.conf”   
“/home/${USERNAME}/.zshrc”   
“/home/${USERNAME}/.gitconfig”   
“/home/${USERNAME}/.gitignore_global”

# — Shell profile additions –––––––––––––––––––––––––

# .zshenv ensures PATH is set regardless of .zshrc content

ZSHENV=”/home/${USERNAME}/.zshenv”
if [ ! -f “$ZSHENV” ] || ! grep -q “# DEVBOX PATHS” “$ZSHENV”; then
cat > “$ZSHENV” <<‘EOF’

# DEVBOX PATHS

export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin:$HOME/.local/bin:$HOME/.npm-global/bin
export GOPATH=$HOME/go
export EDITOR=nvim
EOF
chown “${USERNAME}:${USERNAME}” “$ZSHENV”
fi

# — Projects directory —————————————————––

sudo -u “$USERNAME” mkdir -p “/home/${USERNAME}/projects”

# — Coding agents ————————————————————

echo “🤖 Installing coding agents…”

# npm global prefix for non-root installs

sudo -u “$USERNAME” mkdir -p “/home/${USERNAME}/.npm-global”
sudo -u “$USERNAME” npm config set prefix “/home/${USERNAME}/.npm-global”

# Claude Code

if ! sudo -u “$USERNAME” bash -c ‘export PATH=$PATH:$HOME/.npm-global/bin && command -v claude’ &>/dev/null; then
echo “🤖 Installing Claude Code…”
sudo -u “$USERNAME” npm install -g @anthropic-ai/claude-code
else
echo “🤖 Claude Code already installed, skipping”
fi

# Codex

if ! sudo -u “$USERNAME” bash -c ‘export PATH=$PATH:$HOME/.npm-global/bin && command -v codex’ &>/dev/null; then
echo “🤖 Installing Codex…”
sudo -u “$USERNAME” npm install -g @openai/codex
else
echo “🤖 Codex already installed, skipping”
fi

# OpenCode

if ! sudo -u “$USERNAME” bash -c ‘export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin && command -v opencode’ &>/dev/null; then
echo “🤖 Installing OpenCode…”
sudo -u “$USERNAME” bash -c ‘export PATH=$PATH:/usr/local/go/bin && export GOPATH=$HOME/go && go install github.com/opencode-ai/opencode@latest’
else
echo “🤖 OpenCode already installed, skipping”
fi

# — Done ———————————————————————

echo “”
echo “==============================================”
echo “✅ Devbox ready!”
echo “==============================================”
echo “”
echo “  User:     ${USERNAME}”
echo “  Shell:    zsh + oh-my-zsh”
echo “  Editor:   nvim”
echo “  Projects: ~/projects”
echo “”
echo “  SSH in:   ssh ${USERNAME}@<this-ip>”
echo “  Mosh in:  mosh ${USERNAME}@<this-ip>”
echo “”
echo “  Next steps:”
echo “    1. Log out and SSH back in as ${USERNAME}”
echo “    2. Set your API keys:”
echo “       export ANTHROPIC_API_KEY=…”
echo “       export OPENAI_API_KEY=…”
echo “    3. cd ~/projects && start building!”
echo “”
