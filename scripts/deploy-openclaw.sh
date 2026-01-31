#!/bin/bash
#
# deploy-openclaw.sh - Master deployment script
#
# Usage:
#   ./deploy-openclaw.sh ec2              # Provision new EC2 + deploy
#   ./deploy-openclaw.sh vps <IP>         # Deploy to existing VPS
#   ./deploy-openclaw.sh deploy <IP>      # Just deploy (skip provisioning)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Commands:"
  echo "  ec2              Provision new EC2 instance and deploy OpenClaw"
  echo "  vps <IP>         Deploy OpenClaw to existing VPS at <IP>"
  echo "  deploy <IP>      Run deployment script on server at <IP>"
  echo "  status <IP>      Check deployment status on server"
  echo ""
  echo "Examples:"
  echo "  $0 ec2                    # Full EC2 provisioning + deploy"
  echo "  $0 vps 1.2.3.4            # Deploy to VPS at 1.2.3.4"
  echo "  $0 deploy moltbot-ec2     # Deploy using SSH alias"
  echo ""
  exit 1
}

provision_ec2() {
  echo -e "${GREEN}Provisioning EC2...${NC}"
  bash "$SCRIPT_DIR/provision-ec2.sh"

  if [[ -f /tmp/openclaw-elastic-ip.txt ]]; then
    ELASTIC_IP=$(cat /tmp/openclaw-elastic-ip.txt)
    echo ""
    echo -e "${GREEN}EC2 provisioned at $ELASTIC_IP${NC}"
    echo ""
    read -p "Deploy OpenClaw now? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
      deploy_to_server "$ELASTIC_IP"
    fi
  fi
}

deploy_to_server() {
  local SERVER="$1"
  local SSH_KEY="${SSH_KEY:-~/.ssh/cldy.pem}"

  echo -e "${GREEN}Deploying to $SERVER...${NC}"

  # Determine SSH command
  if [[ "$SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SSH_CMD="ssh -i $SSH_KEY ubuntu@$SERVER"
  else
    SSH_CMD="ssh $SERVER"
  fi

  # Test connection
  echo "Testing SSH connection..."
  if ! $SSH_CMD "echo 'SSH OK'" 2>/dev/null; then
    echo -e "${RED}Cannot connect to $SERVER${NC}"
    exit 1
  fi

  # Copy and run deployment script
  echo "Running deployment script..."
  $SSH_CMD 'bash -s' < "$SCRIPT_DIR/deploy-openclaw-remote.sh"

  echo ""
  echo -e "${GREEN}Deployment complete!${NC}"
}

check_status() {
  local SERVER="$1"

  if [[ "$SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SSH_CMD="ssh -i ~/.ssh/cldy.pem ubuntu@$SERVER"
  else
    SSH_CMD="ssh $SERVER"
  fi

  echo -e "${GREEN}Checking status on $SERVER...${NC}"
  echo ""

  $SSH_CMD << 'EOF'
echo "=== Docker Containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "=== OpenClaw Version ==="
docker exec moltbot node dist/index.js --version 2>/dev/null || echo "Container not running"
echo ""
echo "=== Channel Status ==="
docker exec moltbot node dist/index.js channels status 2>/dev/null || echo "Container not running"
echo ""
echo "=== System Info ==="
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"
echo "Disk: $(df -h / | tail -1 | awk '{print $4 " free"}')"
EOF
}

# Main
case "${1:-}" in
  ec2)
    provision_ec2
    ;;
  vps|deploy)
    [[ -z "${2:-}" ]] && usage
    deploy_to_server "$2"
    ;;
  status)
    [[ -z "${2:-}" ]] && usage
    check_status "$2"
    ;;
  *)
    usage
    ;;
esac
