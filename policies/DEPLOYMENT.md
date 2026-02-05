# Deployment Policies

**Scope:** Pre-deployment requirements, deployment gating, rollback procedures

---

## Critical Rule

**Before deploying ANY change:** Read `DEPLOYMENT.md` or `ARCHITECTURE.md` in the project root, or ask the user first.

---

## Pre-Deployment Checklist

### Required Documentation Review

Before deploying, check for and review these files in the project (or parent directories):

- `DEPLOYMENT.md` - Deployment-specific instructions
- `ARCHITECTURE.md` - System architecture and constraints
- `README.md` - Project-specific deployment notes
- `.github/workflows/` - CI/CD pipeline configuration

**If these don't exist or are unclear:** ASK the user before proceeding.

---

## Deployment Gating

### Automated Gates (Must Pass)

- [ ] **Tests pass:** All unit, integration, and E2E tests green
- [ ] **Linting passes:** No linting errors (warnings acceptable with justification)
- [ ] **Build succeeds:** Clean build with no errors
- [ ] **Security scan:** No critical/high vulnerabilities introduced
- [ ] **Type checking:** No TypeScript/type errors (if applicable)

### Manual Gates (User Confirmation Required)

- [ ] **Schema migrations:** Database changes reviewed and tested
- [ ] **Breaking API changes:** Backward compatibility verified or versioned
- [ ] **Infrastructure changes:** Terraform/ARM templates reviewed
- [ ] **Configuration changes:** Environment variables documented
- [ ] **Dependency updates:** Major version bumps tested in staging

---

## Environment-Specific Requirements

### BriefHours (Azure UK South)

**Infrastructure:**
- Azure Container Apps
- PostgreSQL Flexible Server
- Azure OpenAI

**Deployment Process:**
1. **Staging first:** Always deploy to staging environment
2. **Smoke tests:** Verify critical paths (auth, data access, AI calls)
3. **Database migrations:** Run via migration tool, never manual SQL
4. **Monitor:** Check Application Insights for errors/performance
5. **Production:** Deploy during low-traffic window if possible

**Required Checks:**
- [ ] Container image builds and pushes to ACR
- [ ] Environment variables configured in Container App
- [ ] Managed Identity permissions validated
- [ ] Database connection string updated (if changed)
- [ ] OpenAI endpoint and key configured

---

### Homelab Projects (Mac Mini Cluster)

**Infrastructure:**
- Docker Swarm / standalone containers
- Cloudflare Tunnels for external access
- Self-hosted PostgreSQL
- Komodo for container management

**Deployment Process:**
1. **Build locally:** Test Docker image build
2. **Deploy to staging:** If multi-stage setup exists
3. **Update compose file:** Version tags, environment variables
4. **Deploy:** `docker compose up -d` or Komodo UI
5. **Health check:** Verify service availability via Cloudflare Tunnel

**Required Checks:**
- [ ] Docker image tagged correctly
- [ ] Volume mounts correct (data persistence)
- [ ] Network configuration (bridge/overlay)
- [ ] Cloudflare Tunnel configuration updated
- [ ] Secrets configured (Docker secrets or env files)

---

## Rollback Procedures

### Quick Rollback

If deployment causes issues:

**Azure Container Apps:**
```bash
# Rollback to previous revision
az containerapp revision list --name <app> --resource-group <rg>
az containerapp ingress traffic set --name <app> --resource-group <rg> \
  --revision-weight <previous-revision>=100
```

**Docker (Homelab):**
```bash
# Rollback to previous image version
docker compose pull  # Get previous tag
docker compose up -d --force-recreate
```

### Database Rollback

**If migrations applied:**
1. Check if migration is reversible
2. Run down/rollback migration
3. Restore from backup if necessary

**Backup locations:**
- Azure PostgreSQL: Automated backups (7-35 days retention)
- Homelab PostgreSQL: Check backup schedule in TKNet-Homelab-Docs

---

## Deployment Windows

### BriefHours Production

- **Preferred:** Monday-Thursday, 10:00-16:00 GMT (low traffic)
- **Avoid:** Friday afternoons, weekends (reduced support availability)
- **Emergency:** Any time, with user notification

### Homelab

- **Anytime:** Low user impact
- **Notify if:** Changes affect Charlotte's access to shared services

---

## Post-Deployment Verification

After successful deployment:

1. **Smoke tests:**
   - [ ] Application loads
   - [ ] Authentication works
   - [ ] Core features functional
   - [ ] Database connectivity verified

2. **Monitoring:**
   - [ ] Error rates normal (check logs/Application Insights)
   - [ ] Response times acceptable
   - [ ] Resource usage within expected range

3. **Documentation:**
   - [ ] Update CHANGELOG.md (if exists)
   - [ ] Note any manual steps taken
   - [ ] Update Obsidian project notes with learnings

---

## Emergency Procedures

If deployment causes production outage:

1. **Immediate rollback** (see Rollback Procedures above)
2. **Notify stakeholders** (Charlotte if BNX/BriefHours affected)
3. **Check monitoring** for root cause
4. **Create incident log** in Obsidian vault
5. **Fix and test** in staging before re-deploying

---

## Questions?

- Infrastructure architecture: See `~/.claude/architecture/INFRASTRUCTURE.md`
- Project-specific deployment: Read project's `DEPLOYMENT.md`
- Homelab details: `~/git-bnx/TKN/TKNet-Homelab-Docs/`
