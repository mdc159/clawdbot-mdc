# Deploy OpenClaw

Automated deployment of OpenClaw to a fresh EC2 instance or VPS.

## Usage

```
/deploy-openclaw [target]
```

Where `target` is:
- `ec2` - Provision new AWS EC2 instance (requires AWS CLI configured)
- `vps` - Deploy to existing VPS (provide IP)
- `--help` - Show this help

## What This Does

### Phase 1: Provision Infrastructure (EC2 only)
1. Create security group with ports 22, 18789
2. Launch t3.micro instance with Ubuntu 24.04
3. Allocate and associate Elastic IP
4. Wait for instance to be ready

### Phase 2: Server Setup
1. Set ubuntu password (CRITICAL - do this before any SSH changes)
2. Update system packages
3. Install build-essential, jq, htop, git
4. Install Homebrew (Linuxbrew) + gcc (required for skills)
5. Install Docker
6. Install fail2ban
7. Configure UFW firewall (ports 22, 18789)

### Phase 3: Deploy OpenClaw
1. Clone the repository
2. Build Docker image
3. Create data directory with correct permissions
4. Start container with proper mounts and port bindings

### Phase 4: Configure
1. Run initial gateway setup
2. Configure Telegram bot (if token provided)
3. Verify deployment

## Prerequisites

For EC2 deployment:
- AWS CLI configured (`aws configure`)
- Key pair exists (`~/.ssh/cldy.pem`)

For VPS deployment:
- SSH access to target server
- Root or sudo access

## Scripts

This skill uses:
- `scripts/provision-ec2.sh` - AWS infrastructure provisioning
- `scripts/deploy-openclaw-remote.sh` - Server-side deployment script

## Environment Variables

```bash
# Required for Telegram
TELEGRAM_BOT_TOKEN=your_bot_token

# Optional
OPENCLAW_PORT=18789
OPENCLAW_BIND=lan
```

## Quick Deploy (One-Liner)

After EC2 is provisioned with Elastic IP:

```bash
# From local machine
ssh ubuntu@<ELASTIC_IP> 'bash -s' < scripts/deploy-openclaw-remote.sh
```

## Homebrew and Skills

OpenClaw skills (like `nano-banana-pro` for image generation, `clawhub`, `obsidian`) often require dependencies installed via Homebrew. The deployment script installs:

- **Homebrew** (Linuxbrew on Ubuntu)
- **build-essential** (compilers needed by Homebrew)
- **gcc** (via `brew install gcc`)

This enables API-based skills to work from the EC2 server - they make HTTP calls to external services (Google, OpenAI, etc.) and don't require a desktop environment.

## Lessons Learned (Baked In)

These mistakes are prevented by the scripts:

1. **Elastic IP allocated FIRST** - No more chasing dynamic IPs
2. **Ubuntu password set FIRST** - Before any SSH/security changes
3. **No systemd SSH socket changes** - Just use port 22
4. **Correct file permissions** - uid 1000 for Docker node user
5. **Config path is `.openclaw`** - Not `.clawdbot` or `.moltbot`
6. **Homebrew installed** - Skills need it for dependencies

## Post-Deployment

After running the deployment:

1. Run onboarding to configure model provider:
   ```bash
   ssh <host> 'docker exec -it moltbot node dist/index.js onboard'
   ```

2. Verify everything:
   ```bash
   ssh <host> 'docker exec moltbot node dist/index.js channels status'
   ```

3. Access Web UI: `http://<ELASTIC_IP>:18789`

## Rollback

If something goes wrong:

```bash
# Stop and remove container
docker stop moltbot && docker rm moltbot

# Restore from backup
sudo cp -r /home/ubuntu/moltbot-data-backup /home/ubuntu/moltbot-data
sudo chown -R 1000:1000 /home/ubuntu/moltbot-data

# Restart
docker run -d --name moltbot \
  -p 18789:18789 \
  -v /home/ubuntu/moltbot-data:/home/node/.openclaw \
  moltbot:latest node dist/index.js gateway --bind lan --port 18789
```
