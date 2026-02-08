# Quick Reference

**Scope:** Paths, contacts, shortcuts, frequently needed information

---

## Directory Paths

| Item | Path |
|------|------|
| **Claude profile** | `~/.claude-profile/` (git repo) |
| **Claude config** | `~/.claude/` (symlinks to profile repo) |
| **Git repositories** | `~/git-bnx/` |
| **BNX projects** | `~/git-bnx/BNX/` |
| **BriefHours** | `~/git-bnx/BriefHours/` |
| **Personal/Homelab** | `~/git-bnx/TKN/` |
| **Homelab docs** | `~/git-bnx/TKN/TKNet-Homelab-Docs/` |
| **Obsidian vault** | `~/personal-obsidian/` |
| **Scratchpad** | `/tmp/claude-1000/-home-sbarker--claude-profile/<session-id>/scratchpad` |

---

## Contacts

| Person | Role | Email |
|--------|------|-------|
| **Simon** | User, Developer | simonbarker@gmail.com |
| **Charlotte** | Partner, Co-runs BNX | (ask if needed) |

---

## Skills Reference

Load with `/<skill-name>`:

| Skill | Purpose | When to Use |
|-------|---------|-------------|
| `/profile-reference` | MCP servers, router, statusline | When you need detailed Claude profile feature docs |
| `/bwdangerunlock` | Full Bitwarden vault access | When working with credentials/secrets |
| `/obsidian-ref` | Full vault structure | When navigating Obsidian in detail |
| `/todoist-ref` | API examples, project IDs | When managing Todoist tasks |
| `/ultrathink` | Extended reasoning | Complex architecture decisions, difficult debugging |
| `/z` | Zero-friction commit | Quick commits with AI-generated messages |
| `/imagen` | Image generation | Generate images via Gemini |

---

## Git Configuration

**Account:** `boroughnexus-cto` (single account for all projects now)

**User:**
```
Name: Simon Barker
Email: simon@boroughnexus.com
```

**Default branch:** `main`

---

## Common Commands

### Claude Profile

```bash
# Navigate to profile
cd ~/.claude-profile

# Edit main config
vim ~/.claude/CLAUDE.md

# Load a skill for reference
# (Use Skill tool, not command line)
```

---

### Git

```bash
# Status
git status

# Create branch
git checkout -b feature/name

# Commit
git add .
git commit -m "feat: description"

# Push
git push -u origin feature/name

# Pull request
gh pr create --web
```

---

### Docker

```bash
# List containers
docker ps

# Logs
docker logs -f <container>

# Restart
docker restart <container>

# Compose up
docker compose up -d

# Compose logs
docker compose logs -f
```

---

### Azure CLI

```bash
# Login
az login

# List Container Apps
az containerapp list --resource-group <rg> -o table

# View logs
az containerapp logs show --name <app> --resource-group <rg> --follow

# Update image
az containerapp update --name <app> --resource-group <rg> --image <image>
```

---

## Infrastructure Quick Ref

### BriefHours

| Component | Service | Region |
|-----------|---------|--------|
| **Hosting** | Azure Container Apps | UK South |
| **Database** | PostgreSQL Flexible Server | UK South |
| **AI** | Azure OpenAI | UK South |
| **Monitoring** | Application Insights | UK South |

---

### Homelab

| Component | Service |
|-----------|---------|
| **Hosting** | Mac Mini cluster + Docker |
| **External Access** | Cloudflare Tunnels |
| **Database** | Self-hosted PostgreSQL |
| **Management** | Komodo |

---

## Environment URLs (Examples)

**BriefHours:**
- Production: `https://briefhours.com` (or actual domain)
- API: `https://api.briefhours.com`
- Azure Portal: `https://portal.azure.com`

**Homelab:**
- Komodo: `https://komodo.yourdomain.com` (via Cloudflare Tunnel)
- Monitoring: `https://monitoring.yourdomain.com`

---

## Shortcuts & Aliases

### Recommended Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Navigation
alias cdgit='cd ~/git-bnx'
alias cdbnx='cd ~/git-bnx/BNX'
alias cdbh='cd ~/git-bnx/BriefHours'
alias cdtkn='cd ~/git-bnx/TKN'
alias cdob='cd ~/personal-obsidian'

# Docker
alias dps='docker ps'
alias dlog='docker logs -f'
alias dcu='docker compose up -d'
alias dcd='docker compose down'

# Git
alias gst='git status'
alias gco='git checkout'
alias gaa='git add .'
alias gcm='git commit -m'
alias gp='git push'
alias gl='git pull'
```

---

## Abbreviations

| Abbrev | Meaning |
|--------|---------|
| **ppp** | Puppeteer |
| **BNX** | BoroughNexus |
| **BH** | BriefHours |
| **TKN** | TKN (personal/homelab org) |
| **ADR** | Architectural Decision Record |
| **PARA** | Projects, Areas, Resources, Archive |
| **MCP** | Model Context Protocol |

---

## Documentation Navigation

| Topic | File |
|-------|------|
| **Overview & Navigation** | `~/.claude/CLAUDE.md` |
| **Security & Credentials** | `~/.claude/policies/SECURITY.md` |
| **Deployment** | `~/.claude/policies/DEPLOYMENT.md` |
| **Repo Coupling** | `~/.claude/policies/COUPLING.md` |
| **Infrastructure** | `~/.claude/architecture/INFRASTRUCTURE.md` |
| **Repo Topology** | `~/.claude/architecture/TOPOLOGY.md` |
| **Operations Runbook** | `~/.claude/operations/RUNBOOK.md` |
| **Obsidian Usage** | `~/.claude/operations/OBSIDIAN.md` |
| **This File** | `~/.claude/reference/QUICK_REF.md` |

---

## Emergency Contacts & Procedures

### Service Down

1. Check status (Azure Portal or `docker ps`)
2. View logs (`az containerapp logs` or `docker logs`)
3. Attempt restart
4. Check monitoring (Application Insights or system logs)
5. Notify Charlotte if customer-impacting (BriefHours/BNX)

### Security Incident

1. **Rotate compromised credentials immediately**
2. Check access logs for unauthorized usage
3. Update incident log in Obsidian vault
4. Review and update security policies

### Data Loss Risk

1. **Stop making changes**
2. Check backup availability
3. Restore from most recent backup
4. Document incident and prevention steps

---

## Common File Locations

### Configuration Files

| File | Location |
|------|----------|
| **Global git config** | `~/.gitconfig` |
| **Docker compose** | `<project>/docker-compose.yml` |
| **Environment vars** | `<project>/.env` (git-ignored) |
| **Claude keybindings** | `~/.claude/keybindings.json` |

---

### Project-Specific

| File | Purpose |
|------|---------|
| `README.md` | Project overview, setup |
| `ARCHITECTURE.md` | System design |
| `DEPLOYMENT.md` | Deployment procedures |
| `CONTRIBUTING.md` | Contribution guidelines |
| `.env.example` | Environment variable template |

---

## Timezone

**Primary:** GMT / BST (UK)

---

## Monitoring & Health Checks

### BriefHours

- **Application Insights:** Azure Portal → Monitor → Application Insights
- **Health endpoint:** `https://api.briefhours.com/health` (example)

### Homelab

- **Komodo:** Web UI for container status
- **System:** `docker ps`, `df -h`, `free -h`

---

## Backup Locations

### BriefHours (Azure)

- **Database:** Automated backups (7-35 day retention)
- **Configuration:** Git repositories (infrastructure-as-code)

### Homelab

- **Database:** Restic to NAS (daily)
- **Configuration:** Git repositories
- **Offsite:** Backblaze B2 or similar

---

## Support Resources

### Claude Code

- **Help:** `/help` command or `~/.claude/CLAUDE.md`
- **Issues:** https://github.com/anthropics/claude-code/issues
- **Docs:** Load `/profile-reference` for MCP/router/statusline

### Azure

- **Portal:** https://portal.azure.com
- **Docs:** https://learn.microsoft.com/azure
- **Status:** https://status.azure.com

### Docker

- **Docs:** https://docs.docker.com
- **Hub:** https://hub.docker.com

---

## Version Information

| Tool | Version Notes |
|------|---------------|
| **Node.js** | 18+ preferred |
| **PostgreSQL** | 14+ |
| **Docker** | Latest stable |
| **Azure CLI** | Latest via package manager |

---

## Notes

- **Scratchpad:** Use session-specific scratchpad directory for temporary files
- **Secrets:** Never commit `.env` files or credentials
- **Git history:** Avoid force-push to main/master
- **Documentation:** Append to existing docs when possible

---

## Last Updated

This reference is automatically maintained as part of the Claude profile.

For detailed information on any topic, see the full documentation files listed above.
