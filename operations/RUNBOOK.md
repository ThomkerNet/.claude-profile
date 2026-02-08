# Operational Runbook

**Scope:** Common commands, workflows, troubleshooting procedures

---

## Git Operations

### Common Workflows

**Start new feature:**
```bash
git checkout -b feature/feature-name
# Make changes
git add .
git commit -m "Add feature description"
git push -u origin feature/feature-name
```

**Update branch with latest main:**
```bash
git checkout main
git pull
git checkout feature/feature-name
git rebase main
# Resolve conflicts if any
git push --force-with-lease
```

**Create Pull Request:**
```bash
gh pr create --title "Feature: Description" --body "Details..."
# OR
gh pr create --web  # Opens browser
```

**Review PR:**
```bash
gh pr view 123
gh pr checkout 123
gh pr review 123 --approve
gh pr merge 123
```

---

### Commit Messages

**Format:**
```
<type>: <subject>

<optional body>

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `refactor:` Code refactoring
- `test:` Adding/updating tests
- `chore:` Maintenance, dependencies

**Examples:**
```bash
git commit -m "feat: add user authentication"
git commit -m "fix: resolve timeout in API calls"
git commit -m "docs: update deployment instructions"
```

---

## Docker Operations

### Common Commands

**Build and run:**
```bash
# Build image
docker build -t myapp:latest .

# Run container
docker run -d -p 8080:8080 --name myapp myapp:latest

# View logs
docker logs -f myapp

# Stop and remove
docker stop myapp
docker rm myapp
```

**Docker Compose:**
```bash
# Start services
docker compose up -d

# View logs
docker compose logs -f

# Restart service
docker compose restart api

# Stop all
docker compose down

# Rebuild and restart
docker compose up -d --build
```

---

### Troubleshooting

**Container won't start:**
```bash
# Check logs
docker logs <container-name>

# Inspect container
docker inspect <container-name>

# Check if port is in use
lsof -i :8080
```

**Out of disk space:**
```bash
# Clean up unused resources
docker system prune -a --volumes

# Check disk usage
docker system df
```

**Network issues:**
```bash
# List networks
docker network ls

# Inspect network
docker network inspect bridge

# Connect container to network
docker network connect <network> <container>
```

---

## Database Operations

### PostgreSQL (Homelab)

**Connect:**
```bash
# Via docker
docker exec -it postgres psql -U postgres

# Direct connection
psql -h localhost -U postgres -d mydb
```

**Common queries:**
```sql
-- List databases
\l

-- Connect to database
\c mydb

-- List tables
\dt

-- Describe table
\d tablename

-- Check table size
SELECT pg_size_pretty(pg_total_relation_size('tablename'));
```

**Backup:**
```bash
# Dump database
docker exec postgres pg_dump -U postgres mydb > backup.sql

# Restore
docker exec -i postgres psql -U postgres mydb < backup.sql
```

---

### Azure PostgreSQL (BriefHours)

**Connect:**
```bash
psql "postgresql://user@server.postgres.database.azure.com:5432/dbname?sslmode=require"
```

**Backup/Restore:**
```bash
# Via Azure CLI
az postgres flexible-server backup create \
  --resource-group <rg> \
  --name <server> \
  --backup-name manual-backup-$(date +%Y%m%d)

# Restore (creates new server)
az postgres flexible-server restore \
  --resource-group <rg> \
  --name <new-server> \
  --source-server <original-server> \
  --restore-time "2024-01-15T12:00:00Z"
```

---

## Azure Operations (BriefHours)

### Container Apps

**List apps:**
```bash
az containerapp list --resource-group <rg> -o table
```

**View logs:**
```bash
az containerapp logs show \
  --name <app> \
  --resource-group <rg> \
  --follow
```

**Scale:**
```bash
# Set min/max replicas
az containerapp update \
  --name <app> \
  --resource-group <rg> \
  --min-replicas 1 \
  --max-replicas 5
```

**Update image:**
```bash
az containerapp update \
  --name <app> \
  --resource-group <rg> \
  --image <registry>.azurecr.io/myapp:latest
```

**Rollback:**
```bash
# List revisions
az containerapp revision list \
  --name <app> \
  --resource-group <rg> \
  -o table

# Set traffic to previous revision
az containerapp ingress traffic set \
  --name <app> \
  --resource-group <rg> \
  --revision-weight <revision>=100
```

---

### Key Vault

**List secrets:**
```bash
az keyvault secret list --vault-name <vault> -o table
```

**Get secret:**
```bash
az keyvault secret show --vault-name <vault> --name <secret>
```

**Set secret:**
```bash
az keyvault secret set \
  --vault-name <vault> \
  --name <secret> \
  --value "secret-value"
```

---

## Cloudflare Tunnel (Homelab)

**Status:**
```bash
# Check running tunnels
cloudflared tunnel list

# Check tunnel health
cloudflared tunnel info <tunnel-id>
```

**Restart:**
```bash
# Via systemd (if configured)
sudo systemctl restart cloudflared

# Via docker
docker restart cloudflare-tunnel
```

**View logs:**
```bash
# Systemd
sudo journalctl -u cloudflared -f

# Docker
docker logs -f cloudflare-tunnel
```

---

## Bitwarden (Credential Management)

Load `/bwdangerunlock` for vault access details.

**Quick commands:**
```bash
# Login
bw login

# Unlock vault
bw unlock

# Get item
bw get item "item-name"

# Get password
bw get password "item-name"

# Sync vault
bw sync
```

---

## Common Troubleshooting

### Port Already in Use

```bash
# Find process using port
lsof -i :8080

# Kill process
kill -9 <PID>

# Or use different port
docker run -p 8081:8080 myapp
```

---

### Permission Denied (Docker)

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Logout and login for changes to take effect
```

---

### Git Push Fails

**"Repository not found" or authentication failure:**

- Check you're using the correct account (should be `boroughnexus-cto`)
- Re-authenticate:
  ```bash
  gh auth login
  ```

**"Rejected - non-fast-forward":**
```bash
# Pull latest changes
git pull --rebase

# Resolve conflicts if any
# Then push
git push
```

---

### Database Connection Timeout

**Homelab:**
```bash
# Check container is running
docker ps | grep postgres

# Check network
docker network inspect bridge

# Test connection
psql -h localhost -U postgres -c "SELECT 1"
```

**Azure:**
```bash
# Check firewall rules
az postgres flexible-server firewall-rule list \
  --resource-group <rg> \
  --name <server>

# Check server status
az postgres flexible-server show \
  --resource-group <rg> \
  --name <server>
```

---

## Monitoring & Health Checks

### Homelab Services

**Check running containers:**
```bash
docker ps
# or
docker compose ps
```

**Check system resources:**
```bash
# Disk space
df -h

# Memory
free -h

# CPU
top
# or
htop
```

**Container resource usage:**
```bash
docker stats
```

---

### BriefHours (Azure)

**Application Insights:**
```bash
# View in portal
az portal

# Query logs
az monitor app-insights query \
  --app <app-insights-name> \
  --analytics-query "requests | take 100"
```

**Health endpoint:**
```bash
# Check API health
curl https://briefhours-api.azurecontainerapps.io/health
```

---

## Deployment Shortcuts

### Quick Deploy (Homelab)

```bash
# Pull latest, rebuild, restart
git pull && docker compose up -d --build
```

### Quick Deploy (BriefHours)

```bash
# Build, push, update (from project root)
docker build -t <registry>.azurecr.io/myapp:latest .
docker push <registry>.azurecr.io/myapp:latest
az containerapp update \
  --name <app> \
  --resource-group <rg> \
  --image <registry>.azurecr.io/myapp:latest
```

---

## Useful Aliases (Optional)

Add to `~/.bashrc` or `~/.zshrc`:

```bash
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

# Azure
alias azps='az containerapp list -o table'
```

---

## Emergency Procedures

### Service Down (Homelab)

1. Check container status: `docker ps -a`
2. View logs: `docker logs <container>`
3. Restart: `docker restart <container>`
4. If database issue: Check PostgreSQL logs
5. If network issue: Check Cloudflare Tunnel status

---

### Service Down (BriefHours)

1. Check Azure status: `az containerapp show --name <app> --resource-group <rg>`
2. View logs: `az containerapp logs show --name <app> --resource-group <rg> --follow`
3. Check Application Insights for errors
4. Rollback if needed (see Azure Operations above)
5. Notify Charlotte if customer-impacting

---

## References

| Topic | Location |
|-------|----------|
| **Deployment procedures** | `~/.claude/policies/DEPLOYMENT.md` |
| **Infrastructure details** | `~/.claude/architecture/INFRASTRUCTURE.md` |
| **Security/credentials** | `~/.claude/policies/SECURITY.md` |
| **Homelab docs** | `~/git-bnx/TKN/TKNet-Homelab-Docs/` |
| **Bitwarden usage** | Load `/bwdangerunlock` |
