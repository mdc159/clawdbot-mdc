# OpenClaw EC2 Deployment

This documents the OpenClaw (formerly Moltbot/Clawdbot) deployment on the EC2 instance.

## Server Details

- **Host**: 3.131.112.190 (Elastic IP, us-east-2)
- **Access**: `ssh moltbot-ec2`
- **Node**: v22.22.0

### Security
- **fail2ban**: Enabled (blocks brute force SSH attempts)
- **UFW firewall**: Enabled (ports 22, 2222, 18789 allowed)

## Architecture

OpenClaw runs as a **Docker container** with persistent config mounted from the host.

```
┌─────────────────────────────────────────────┐
│  EC2 Instance                               │
│                                             │
│  /home/ubuntu/clawdbot-mdc/                 │
│  └── Source repo (synced with upstream)    │
│                                             │
│  /home/ubuntu/moltbot-data/                 │
│  └── Persistent config (mounted)            │
│                                             │
│  ┌───────────────────────────────────────┐  │
│  │  Docker: moltbot                      │  │
│  │  - Image: moltbot:latest (OpenClaw)   │  │
│  │  - Port: 18789                        │  │
│  │  - /home/node/.openclaw → moltbot-data│  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

## Current State

| Component | Version | Location |
|-----------|---------|----------|
| Source repo | 2026.1.30 | `/home/ubuntu/clawdbot-mdc` |
| Docker image | 2026.1.30 | `moltbot:latest` |
| Config | — | `/home/ubuntu/moltbot-data` |
| Backup | — | `/home/ubuntu/moltbot-data-backup` |

## Key Paths

```
/home/ubuntu/
├── clawdbot-mdc/          # Source repo (git clone, synced with upstream)
├── moltbot-data/          # Persistent config (Docker volume)
│   ├── openclaw.json      # Main config (NEW NAME)
│   ├── agents/            # Agent data
│   ├── devices/           # Paired devices
│   └── identity/          # Device identity
└── moltbot-data-backup/   # Config backup
```

## Quick Start Cheat Sheet

### Full Rebuild + Restart (one-liner)

```bash
cd /home/ubuntu/clawdbot-mdc && git fetch upstream && git merge upstream/main --no-edit && docker build -t moltbot:latest . && docker stop moltbot && docker rm moltbot && docker run -d --name moltbot -p 18789:18789 -v /home/ubuntu/moltbot-data:/home/node/.openclaw moltbot:latest node dist/index.js gateway --bind lan --port 18789
```

### Run Onboarding

```bash
docker exec -it moltbot node dist/index.js onboard
```

**Key choices during onboarding:**

| Prompt | Recommended Choice |
|--------|-------------------|
| Security warning | Yes (continue) |
| Onboarding mode | QuickStart |
| Config handling | Use existing (keeps Telegram) |
| Model provider | OpenRouter |
| Auth method | API Key |

### Chat with the Bot

**Terminal:**
```bash
docker exec moltbot node dist/index.js agent --message "Hello"
```

**Web UI:**
```
http://3.131.112.190:18789
```

**Telegram:**
DM `@pimpshizzleBot`

### Verify Everything

```bash
# Channel status
docker exec moltbot node dist/index.js channels status

# Logs
docker logs moltbot --tail 30

# Health check
curl http://localhost:18789/
```

## Docker Commands

### Check Status
```bash
docker ps
docker logs moltbot --tail 50
```

### Restart Container
```bash
docker restart moltbot
```

### Enter Container
```bash
docker exec -it moltbot sh
```

### Start Container (if stopped)
```bash
docker run -d --name moltbot \
  -p 18789:18789 \
  -v /home/ubuntu/moltbot-data:/home/node/.openclaw \
  moltbot:latest node dist/index.js gateway --bind lan --port 18789
```

## Rebuild from Source

When the source repo is updated and you need to rebuild:

```bash
cd /home/ubuntu/clawdbot-mdc

# Sync with upstream (moltbot/moltbot)
git fetch upstream
git merge upstream/main --no-edit

# Rebuild Docker image
docker build -t moltbot:latest .

# Stop and remove old container
docker stop moltbot && docker rm moltbot

# Start new container
docker run -d --name moltbot \
  -p 18789:18789 \
  -v /home/ubuntu/moltbot-data:/home/node/.openclaw \
  moltbot:latest node dist/index.js gateway --bind lan --port 18789

# Verify
docker logs moltbot --tail 20
```

## Configuration

### Model Provider
- **Provider**: Not configured (run onboarding to set up OpenRouter)
- **Status**: Gateway running, but no AI model connected yet

### Gateway
- **Mode**: local
- **Port**: 18789
- **Bind**: lan (0.0.0.0)
- **Auth Token**: `d598088bfc9340007cfc167109d895eb`

### Channels
- **Telegram**: `@pimpshizzleBot` (configured, running)

## Backup & Restore

### Create Backup
```bash
sudo cp -r /home/ubuntu/moltbot-data /home/ubuntu/moltbot-data-backup-$(date +%Y%m%d)
sudo chown -R 1000:1000 /home/ubuntu/moltbot-data-backup-*
```

### Restore from Backup
```bash
docker stop moltbot
sudo cp -r /home/ubuntu/moltbot-data-backup /home/ubuntu/moltbot-data
sudo chown -R 1000:1000 /home/ubuntu/moltbot-data
docker start moltbot
```

## Troubleshooting

### Check if Gateway is Running
```bash
ss -tlnp | grep 18789
docker exec moltbot node dist/index.js channels status
```

### View Logs
```bash
docker logs moltbot --tail 100 -f
```

### Fix Permission Issues
The container runs as user `node` (uid 1000). If you see EACCES errors:
```bash
sudo chown -R 1000:1000 /home/ubuntu/moltbot-data
docker restart moltbot
```

### Common Issues

**"Missing config" error**
- Ensure `openclaw.json` exists (not just `clawdbot.json`)
- Config must have `gateway.mode` and `gateway.auth.token` set

**"No API key found for provider"**
- Run onboarding: `docker exec -it moltbot node dist/index.js onboard`

**Container won't start**
- Check logs: `docker logs moltbot`
- Verify port isn't in use: `ss -tlnp | grep 18789`

**Telegram not responding**
- Check bot is running: `docker exec moltbot node dist/index.js channels status`
- Verify token in config: `cat /home/ubuntu/moltbot-data/openclaw.json`

**Build fails with TypeScript errors**
- Sync with upstream: `git fetch upstream && git merge upstream/main`

## Git Remotes

```bash
origin    https://github.com/mdc159/clawdbot-mdc.git   # Your fork
upstream  https://github.com/moltbot/moltbot.git       # Main repo (OpenClaw)
```

To sync with upstream:
```bash
git fetch upstream
git merge upstream/main --no-edit
git push origin main  # Optional: push to your fork
```

## Automated Deployment

For fresh deployments, use the automated scripts instead of manual setup:

### New EC2 Instance
```bash
# From local machine (requires AWS CLI configured)
./scripts/deploy-openclaw.sh ec2
```

### Existing VPS
```bash
# Deploy to any server with SSH access
./scripts/deploy-openclaw.sh vps <IP_ADDRESS>

# Or use SSH alias
./scripts/deploy-openclaw.sh deploy moltbot-ec2
```

### Check Status
```bash
./scripts/deploy-openclaw.sh status moltbot-ec2
```

### What the Scripts Do

1. **Set ubuntu password FIRST** (critical for sudo/recovery)
2. Install Docker, fail2ban, UFW
3. Clone and build OpenClaw
4. Start container with correct mounts/permissions
5. Configure firewall (ports 22, 18789)

See `scripts/deploy-openclaw.sh`, `scripts/provision-ec2.sh`, `scripts/deploy-openclaw-remote.sh`

## Incident Reports

- **INCIDENT-2026-01-31.md** - SSH lockout due to botched port change, EBS volume swap recovery

## History

- **2026-01-28**: Initial Docker deployment (v2026.1.24-1 as Moltbot)
- **2026-01-31**: Cleaned up orphaned npm stub and stale repos
- **2026-01-31**: Configured Telegram bot (@pimpshizzleBot)
- **2026-01-31**: Synced with upstream, upgraded to OpenClaw v2026.1.30
- **2026-01-31**: Updated config path from `.clawdbot` to `.openclaw`
- **2026-01-31**: Added security hardening (fail2ban, UFW), allocated Elastic IP (3.131.112.190)
- **2026-01-31**: SSH lockout incident (see INCIDENT-2026-01-31.md), recovered via EBS swap
- **2026-01-31**: Created automated deployment scripts
