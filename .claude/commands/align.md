# Align

Align the local codebase with what's deployed on the VPS/EC2 instance.

## Purpose

This command audits the difference between what the codebase expects to be deployed and what's actually running on the remote server, then creates an action plan to bring them into alignment.

## Usage

```
/align
```

## What this command does

### Phase 1: Understand Local Expectations

Use explorer agents to scan the codebase for deployment context:

1. **Read key documentation files** (in parallel):
   - `CLAUDE.md` - Project structure and deployment notes
   - `README.md` - Setup and deployment instructions
   - `CHANGELOG.md` or `HISTORY.md` - Recent changes that should be deployed
   - `DEVLOG.md` or `dev-log.md` - Development notes and deployment status
   - `.env.example` - Expected environment variables
   - `package.json` / `requirements.txt` - Dependencies

2. **Identify deployment artifacts**:
   - Build outputs (dist/, build/, etc.)
   - Configuration files that need to sync
   - Scripts that should be present
   - Services/processes that should be running

### Phase 2: Audit Remote Server

SSH into the VPS/EC2 and gather current state:

```bash
# Connect to the server (adjust as needed)
ssh -i ~/.ssh/cldy.pem ubuntu@<server-ip>
```

Check the following on the remote:
- Current deployed code version (git log, package.json version)
- Running processes (`pm2 list`, `systemctl status`, `docker ps`)
- Installed dependencies
- Environment variables configured
- File structure and permissions
- Service health and logs

### Phase 3: Generate Differential Report

Create a comparison showing:

| Aspect | Local/Expected | Remote/Actual | Status |
|--------|---------------|---------------|--------|
| Version | ... | ... | ✅/❌ |
| Dependencies | ... | ... | ✅/❌ |
| Config files | ... | ... | ✅/❌ |
| Services | ... | ... | ✅/❌ |

### Phase 4: Create Alignment Plan

Based on the differential, propose specific steps:

1. **Code sync** - git pull, deploy script, or manual sync
2. **Dependency updates** - npm install, pip install, etc.
3. **Config updates** - Environment variables, config files
4. **Service restarts** - Restart services to pick up changes
5. **Verification** - Commands to verify alignment

## Server Configuration

Default server (uses SSH alias from ~/.ssh/config):
- **OpenClaw EC2**: `ssh moltbot-ec2` (Elastic IP: 3.131.112.190)

Override by specifying in project's CLAUDE.md:
```markdown
## Deployment
- Server: ssh user@your-server-ip
- Deploy path: /var/www/app
```

## Example Output

```
=== ALIGNMENT REPORT ===

Local expects: v1.2.3 (from package.json)
Remote has: v1.2.1

DIFFERENCES FOUND:
- [ ] 2 commits behind (abc123, def456)
- [ ] Missing env var: NEW_API_KEY
- [ ] pm2 process not running: worker

ACTION PLAN:
1. SSH into server
2. cd /home/ubuntu/app && git pull origin main
3. npm install
4. Add NEW_API_KEY to .env
5. pm2 restart all
6. Verify with: pm2 list && curl localhost:3000/health
```
