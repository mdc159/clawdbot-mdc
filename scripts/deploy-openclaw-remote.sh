#!/bin/bash
#
# deploy-openclaw-remote.sh - Deploy OpenClaw on a fresh Ubuntu server
#
# Usage:
#   # Run remotely via SSH
#   ssh ubuntu@<IP> 'bash -s' < deploy-openclaw-remote.sh
#
#   # Or copy and run directly on server
#   scp deploy-openclaw-remote.sh ubuntu@<IP>:~/ && ssh ubuntu@<IP> './deploy-openclaw-remote.sh'
#
# Environment variables (optional):
#   TELEGRAM_BOT_TOKEN - Telegram bot token to configure
#   UBUNTU_PASSWORD - Password to set for ubuntu user (will prompt if not set)
#   SKIP_SECURITY - Set to 1 to skip security hardening
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${CYAN}=== $1 ===${NC}\n"; }

# Configuration
REPO_URL="https://github.com/moltbot/moltbot.git"
INSTALL_DIR="/home/ubuntu/clawdbot-mdc"
DATA_DIR="/home/ubuntu/moltbot-data"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
OPENCLAW_BIND="${OPENCLAW_BIND:-lan}"

section "OPENCLAW DEPLOYMENT SCRIPT"
echo "This script will:"
echo "  1. Set ubuntu password (CRITICAL for sudo)"
echo "  2. Install Docker and security tools"
echo "  3. Clone and build OpenClaw"
echo "  4. Start the gateway container"
echo ""

# ============================================
# PHASE 1: SET PASSWORD FIRST (LESSON LEARNED!)
# ============================================
section "PHASE 1: Set Ubuntu Password"

# CRITICAL: Set password BEFORE any security changes
# This was a hard lesson - without a password, recovery is painful
if [[ -z "$UBUNTU_PASSWORD" ]]; then
  warn "No UBUNTU_PASSWORD set. Generating random password..."
  UBUNTU_PASSWORD=$(openssl rand -base64 12)
  echo ""
  echo -e "${YELLOW}=======================================${NC}"
  echo -e "${YELLOW}  SAVE THIS PASSWORD SOMEWHERE SAFE!  ${NC}"
  echo -e "${YELLOW}=======================================${NC}"
  echo ""
  echo "  Ubuntu password: $UBUNTU_PASSWORD"
  echo ""
  echo -e "${YELLOW}=======================================${NC}"
  echo ""
fi

echo "ubuntu:$UBUNTU_PASSWORD" | sudo chpasswd
log "Ubuntu password set successfully"

# ============================================
# PHASE 2: SYSTEM UPDATES & PACKAGES
# ============================================
section "PHASE 2: System Updates"

log "Updating package lists..."
sudo apt-get update -qq

log "Installing prerequisites..."
sudo apt-get install -y -qq \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  jq \
  htop \
  git \
  build-essential

# ============================================
# PHASE 2.5: HOMEBREW INSTALLATION
# ============================================
section "PHASE 2.5: Homebrew Installation"

if command -v brew &> /dev/null; then
  log "Homebrew already installed: $(brew --version | head -1)"
else
  log "Installing Homebrew (required for OpenClaw skills)..."

  # Non-interactive Homebrew install
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add to PATH for this session
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

  # Add to .bashrc for future sessions
  echo >> /home/ubuntu/.bashrc
  echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/ubuntu/.bashrc

  log "Homebrew installed: $(brew --version | head -1)"

  # Install recommended gcc
  log "Installing gcc via Homebrew..."
  brew install gcc
fi

# Ensure brew is in PATH for rest of script
if [[ -d /home/linuxbrew/.linuxbrew ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# ============================================
# PHASE 3: DOCKER INSTALLATION
# ============================================
section "PHASE 3: Docker Installation"

if command -v docker &> /dev/null; then
  log "Docker already installed: $(docker --version)"
else
  log "Installing Docker..."

  # Add Docker's official GPG key
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  # Add the repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Install Docker
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Add ubuntu to docker group
  sudo usermod -aG docker ubuntu

  log "Docker installed: $(docker --version)"
fi

# ============================================
# PHASE 4: SECURITY HARDENING
# ============================================
if [[ "$SKIP_SECURITY" != "1" ]]; then
  section "PHASE 4: Security Hardening"

  # Install fail2ban
  log "Installing fail2ban..."
  sudo apt-get install -y -qq fail2ban
  sudo systemctl enable fail2ban
  sudo systemctl start fail2ban

  # Configure UFW
  log "Configuring UFW firewall..."
  sudo ufw --force reset >/dev/null
  sudo ufw default deny incoming >/dev/null
  sudo ufw default allow outgoing >/dev/null
  sudo ufw allow 22/tcp >/dev/null      # SSH (keep on 22 - DON'T CHANGE!)
  sudo ufw allow ${OPENCLAW_PORT}/tcp >/dev/null  # OpenClaw gateway
  sudo ufw --force enable >/dev/null

  log "Firewall configured (ports: 22, $OPENCLAW_PORT)"

  # NOTE: We intentionally do NOT change SSH port
  # Lesson learned: Changing SSH port via systemd socket override is dangerous
  # and can lock you out. Just use port 22 with fail2ban.
  warn "SSH remains on port 22 (with fail2ban protection)"
  warn "DO NOT attempt to change SSH port via systemd socket override!"
else
  warn "Skipping security hardening (SKIP_SECURITY=1)"
fi

# ============================================
# PHASE 5: CLONE REPOSITORY
# ============================================
section "PHASE 5: Clone OpenClaw Repository"

if [[ -d "$INSTALL_DIR" ]]; then
  log "Repository exists, pulling latest..."
  cd "$INSTALL_DIR"
  git fetch origin
  git reset --hard origin/main
else
  log "Cloning repository..."
  git clone "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

log "Repository ready at $INSTALL_DIR"

# ============================================
# PHASE 6: BUILD DOCKER IMAGE
# ============================================
section "PHASE 6: Build Docker Image"

cd "$INSTALL_DIR"
log "Building Docker image (this may take a few minutes)..."
sudo docker build -t moltbot:latest .

log "Docker image built successfully"

# ============================================
# PHASE 7: PREPARE DATA DIRECTORY
# ============================================
section "PHASE 7: Prepare Data Directory"

if [[ ! -d "$DATA_DIR" ]]; then
  log "Creating data directory..."
  sudo mkdir -p "$DATA_DIR"
fi

# CRITICAL: Set correct ownership
# Container runs as 'node' user (uid 1000)
log "Setting permissions (uid 1000 for Docker node user)..."
sudo chown -R 1000:1000 "$DATA_DIR"

log "Data directory ready at $DATA_DIR"

# ============================================
# PHASE 8: STOP OLD CONTAINER (if exists)
# ============================================
section "PHASE 8: Container Management"

if sudo docker ps -a --format '{{.Names}}' | grep -q '^moltbot$'; then
  log "Stopping existing container..."
  sudo docker stop moltbot 2>/dev/null || true
  sudo docker rm moltbot 2>/dev/null || true
fi

# ============================================
# PHASE 9: START CONTAINER
# ============================================
section "PHASE 9: Start OpenClaw Container"

log "Starting container..."
sudo docker run -d \
  --name moltbot \
  --restart unless-stopped \
  -p ${OPENCLAW_PORT}:${OPENCLAW_PORT} \
  -v ${DATA_DIR}:/home/node/.openclaw \
  moltbot:latest \
  node dist/index.js gateway --bind ${OPENCLAW_BIND} --port ${OPENCLAW_PORT}

# Wait for container to start
sleep 5

# Check if running
if sudo docker ps --format '{{.Names}}' | grep -q '^moltbot$'; then
  log "Container started successfully"
else
  error "Container failed to start. Check logs: docker logs moltbot"
fi

# ============================================
# PHASE 10: CONFIGURE TELEGRAM (if token provided)
# ============================================
if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
  section "PHASE 10: Configure Telegram"

  log "Setting Telegram bot token..."
  sudo docker exec moltbot node dist/index.js config set telegram.botToken "$TELEGRAM_BOT_TOKEN"
  sudo docker exec moltbot node dist/index.js doctor --fix

  log "Telegram configured"
fi

# ============================================
# DONE!
# ============================================
section "DEPLOYMENT COMPLETE"

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "<your-server-ip>")

echo ""
echo -e "${GREEN}OpenClaw is now running!${NC}"
echo ""
echo "============================================"
echo "  Server Status"
echo "============================================"
echo ""
sudo docker ps --filter name=moltbot --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "============================================"
echo "  Access"
echo "============================================"
echo ""
echo "  Web UI:     http://${PUBLIC_IP}:${OPENCLAW_PORT}"
echo "  SSH:        ssh ubuntu@${PUBLIC_IP}"
echo ""
echo "============================================"
echo "  Next Steps"
echo "============================================"
echo ""
echo "  1. Run onboarding to configure model provider:"
echo "     docker exec -it moltbot node dist/index.js onboard"
echo ""
echo "  2. Check channel status:"
echo "     docker exec moltbot node dist/index.js channels status"
echo ""
echo "  3. View logs:"
echo "     docker logs moltbot --tail 50 -f"
echo ""
if [[ -n "$UBUNTU_PASSWORD" && "$UBUNTU_PASSWORD" != *"*"* ]]; then
  echo "============================================"
  echo -e "  ${YELLOW}REMEMBER YOUR PASSWORD${NC}"
  echo "============================================"
  echo ""
  echo "  Ubuntu password: $UBUNTU_PASSWORD"
  echo ""
fi
echo "============================================"
echo ""
