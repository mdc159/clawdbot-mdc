# OpenClaw Deployment Guide

> **Last Updated**: 2026-01-31
> **Version Tested**: 2026.1.30

This document captures lessons learned from deploying OpenClaw and serves as a guide for subsequent installations.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Installation Methods](#installation-methods)
- [Configuration](#configuration)
- [Security Settings](#security-settings)
- [Troubleshooting](#troubleshooting)
- [Lessons Learned](#lessons-learned)
- [Platform-Specific Notes](#platform-specific-notes)

---

## Quick Start

```bash
# Verify Node.js 22+
node --version

# Install OpenClaw
npm install -g openclaw@latest

# Run onboarding (interactive)
openclaw onboard

# Or non-interactive with API key from environment
openclaw onboard --non-interactive --accept-risk --auth-choice apiKey --anthropic-api-key "$ANTHROPIC_API_KEY"

# Start gateway
openclaw gateway run --verbose

# Verify
openclaw status
```

---

## Prerequisites

### Required

| Dependency | Minimum Version | Check Command |
|------------|-----------------|---------------|
| Node.js | 22.x | `node --version` |
| npm | 10.x | `npm --version` |

### Optional

| Dependency | Purpose |
|------------|---------|
| Tailscale | Remote access without port forwarding |
| Docker | Sandboxed execution |
| systemd | Service management (Linux) |

### Environment Variables

Set these before installation for smoother onboarding:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."  # Optional, for fallback
```

---

## Installation Methods

### Method 1: npm Global Install (Recommended)

```bash
npm install -g openclaw@latest
```

**Pros**: Simple, uses existing Node.js
**Cons**: Requires Node.js 22+, npm deprecation warnings (harmless)

### Method 2: From Source (Development)

```bash
git clone https://github.com/openclaw/openclaw.git
cd openclaw
pnpm install
pnpm build
```

---

## Configuration

### File Locations

| Path | Purpose |
|------|---------|
| `~/.openclaw/openclaw.json` | Main configuration |
| `~/.openclaw/workspace/` | Agent workspace |
| `~/.openclaw/agents/main/sessions/` | Session storage |
| `~/.openclaw/exec-approvals.json` | Command allowlist |
| `~/.openclaw/identity/device.json` | Device identity |

### Configuration via CLI

```bash
# Get a value
openclaw config get tools.exec

# Set a value
openclaw config set tools.exec.security allowlist

# View full config
cat ~/.openclaw/openclaw.json
```

### Minimal Configuration

```json
{
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": 18789
  },
  "tools": {
    "exec": {
      "security": "allowlist",
      "ask": "on-miss"
    }
  },
  "logging": {
    "redactSensitive": "tools"
  }
}
```

---

## Security Settings

### Exec Security Levels

| Level | Behavior | Use Case |
|-------|----------|----------|
| `deny` | No shell commands allowed | Maximum restriction |
| `allowlist` | Only approved commands run | **Recommended for most users** |
| `full` | All commands allowed | Development/testing only |

### Ask Modes

| Mode | Behavior |
|------|----------|
| `off` | Never prompt for approval |
| `on-miss` | Prompt when command not in allowlist |
| `always` | Always prompt before execution |

### Recommended Settings by Use Case

**Learning/Experimentation**:
```json
{
  "tools": {
    "exec": {
      "security": "allowlist",
      "ask": "on-miss"
    }
  }
}
```

**Production/Non-Technical User**:
```json
{
  "tools": {
    "exec": {
      "security": "allowlist",
      "ask": "always"
    },
    "policy": {
      "deny": ["group:fs-write", "group:dangerous"]
    }
  }
}
```

**Development (Full Agency)**:
```json
{
  "tools": {
    "exec": {
      "security": "full",
      "ask": "off"
    }
  }
}
```

---

## Troubleshooting

### Common Issues

#### 1. Onboarding Fails with "gateway closed"

**Symptom**:
```
Error: gateway closed (1006 abnormal closure)
```

**Cause**: Onboarding tries to connect to gateway, but gateway isn't running yet.

**Solution**: This is expected during initial setup. The config is still created. Start the gateway manually:
```bash
openclaw gateway run
```

#### 2. Token Mismatch Warning

**Symptom**:
```
unauthorized: gateway token mismatch
```

**Cause**: The CLI's remote token doesn't match the gateway's auth token.

**Solution**: For local-only use, this can be ignored. For remote access:
```bash
openclaw config set gateway.remote.token "$(openclaw config get gateway.auth.token)"
```

#### 3. npm Deprecation Warnings

**Symptom**: Warnings about deprecated packages during install.

**Cause**: Transitive dependencies use older packages.

**Solution**: These are harmless. The install still succeeds.

#### 4. API Key Not Recognized

**Symptom**: Model errors or "no auth profile" messages.

**Cause**: API key not properly configured.

**Solution**: Ensure environment variable is set:
```bash
echo $ANTHROPIC_API_KEY  # Should show your key
```

Or configure directly:
```bash
openclaw configure --section model
```

#### 5. Port Already in Use

**Symptom**: Gateway fails to start.

**Solution**:
```bash
# Kill existing process
pkill -f openclaw-gateway

# Or use --force
openclaw gateway run --force
```

### Diagnostic Commands

```bash
# Full status
openclaw status

# Security audit
openclaw security audit
openclaw security audit --deep

# Check gateway logs
tail -f /tmp/openclaw-gateway.log

# Verify port binding
ss -ltnp | grep 18789

# Check process
ps aux | grep openclaw
```

---

## Lessons Learned

### Installation Insights

| Date | Issue | Resolution | Notes |
|------|-------|------------|-------|
| 2026-01-31 | npm install takes ~8 minutes | Normal for first install | 759 packages, deprecation warnings are harmless |
| 2026-01-31 | Onboarding errors about gateway | Config still created successfully | Start gateway after onboarding completes |
| 2026-01-31 | API key schema not obvious | Use environment variables | `ANTHROPIC_API_KEY` auto-detected by auth profiles |
| 2026-01-31 | Config validation strict | Use CLI commands to set values | `openclaw config set` handles validation |

### Configuration Tips

1. **Environment variables are easiest for API keys** - The onboarding picks them up automatically via auth profiles.

2. **Use CLI for config changes** - Direct JSON editing can fail validation. Use `openclaw config set path.to.key value`.

3. **Gateway token is auto-generated** - Don't manually set unless you have a specific need.

4. **Restart gateway after config changes** - Most settings require: `pkill -f openclaw-gateway && openclaw gateway run`

### Security Observations

1. **Allowlist mode is a good default** - Provides safety without being too restrictive.

2. **`ask: on-miss` is the sweet spot** - You learn what commands are tried while maintaining control.

3. **Approvals file is created on-demand** - Don't worry if `~/.openclaw/exec-approvals.json` doesn't exist initially.

4. **Security audit is non-intrusive** - Run it freely; it only reads, never modifies.

---

## Platform-Specific Notes

### Linux

- **Systemd service**: Optional, use `openclaw daemon install` for auto-start
- **Logs**: `/tmp/openclaw/openclaw-YYYY-MM-DD.log`
- **Permissions**: User-level install, no root required for basic operation

### macOS (Planned)

- **Menu bar app**: Native experience, no terminal needed
- **iMessage integration**: Uses `imsg` CLI bundled with app
- **Voice wake**: Requires microphone permission
- **Auto-start**: Built into app, no launchd config needed

### Windows (Future)

- Not yet tested in this deployment

---

## Verification Checklist

Use this to verify a successful deployment:

- [ ] `openclaw --version` returns expected version
- [ ] `~/.openclaw/openclaw.json` exists
- [ ] `openclaw gateway run` starts without errors
- [ ] `openclaw status` shows gateway reachable
- [ ] `openclaw security audit` shows no critical issues
- [ ] Dashboard accessible at http://127.0.0.1:18789/
- [ ] `openclaw chat` connects and responds

---

## Updating This Document

This document can be updated via the deployment lessons hook:

```bash
# Add a new lesson
openclaw-lesson "Issue description" "Resolution" "Additional notes"
```

Or manually edit and commit changes.

---

## References

- [Official Docs](https://docs.openclaw.ai/)
- [CLI Reference](https://docs.openclaw.ai/cli)
- [Configuration](https://docs.openclaw.ai/configuration)
- [Troubleshooting](https://docs.openclaw.ai/troubleshooting)
- [Security](https://docs.openclaw.ai/cli/security)
