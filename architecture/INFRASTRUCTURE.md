# Infrastructure Architecture

**Scope:** Cloud environments, hosting platforms, infrastructure decisions

---

## Overview

Different projects use different infrastructure based on their needs, scale, and strategic decisions.

---

## BriefHours (Production SaaS)

**Cloud Provider:** Microsoft Azure
**Region:** UK South
**Strategy:** Managed services for reliability and compliance

### Stack

| Component | Service | Justification |
|-----------|---------|---------------|
| **Application Hosting** | Azure Container Apps | Serverless containers, auto-scaling, simplified deployment |
| **Database** | PostgreSQL Flexible Server | Managed PostgreSQL, automated backups, high availability |
| **AI/LLM** | Azure OpenAI | GPT-4, Claude via Azure, data residency, enterprise SLA |
| **Monitoring** | Application Insights | Integrated APM, logs, metrics, alerts |
| **Authentication** | Azure AD B2C (or custom) | User management, SSO, MFA |
| **Networking** | Virtual Network + Private Link | Secure service-to-service communication |
| **CDN/Edge** | Azure Front Door or Cloudflare | Global distribution, DDoS protection |

### Why Azure?

- **Data residency:** UK South region for UK/EU customers
- **OpenAI access:** Azure OpenAI service availability
- **Enterprise features:** Managed Identity, Key Vault, compliance certifications
- **BNX relationship:** Strategic cloud provider for BriefHours product

---

## BNX & Other Projects (Homelab)

**Infrastructure:** Self-hosted Mac Mini cluster
**External Access:** Cloudflare Tunnels
**Strategy:** Cost control, learning, flexibility

### Stack

| Component | Service | Justification |
|-----------|---------|---------------|
| **Container Orchestration** | Docker Swarm / Standalone | Lightweight, sufficient for homelab scale |
| **Container Management** | Komodo | Web UI for Docker management |
| **Database** | Self-hosted PostgreSQL | Full control, no cloud costs |
| **Reverse Proxy** | Traefik or Nginx | Routing, SSL termination |
| **External Access** | Cloudflare Tunnels | Secure ingress without open ports |
| **Secrets Management** | Bitwarden + Docker Secrets | Centralized credential storage |
| **Monitoring** | Grafana + Prometheus (optional) | Metrics and dashboards |
| **Backups** | Restic / Borg to NAS | Automated, versioned backups |

### Why Homelab?

- **Cost:** No per-hour cloud charges for experimentation
- **Control:** Full infrastructure access, custom configurations
- **Learning:** Hands-on experience with self-hosting
- **Flexibility:** No cloud provider lock-in

---

## Infrastructure Decisions

### ✅ Use Cases by Platform

| Scenario | Platform | Why |
|----------|----------|-----|
| **BriefHours production** | Azure UK South | SLA, compliance, scalability |
| **BNX client projects** | Depends on client requirements | Client's cloud or homelab |
| **Personal projects** | Homelab | Cost, experimentation |
| **Static sites** | Cloudflare Pages | Free, fast CDN, simple deployment |
| **Prototypes/demos** | Homelab | Quick iteration, no cloud costs |

---

### ❌ What We Don't Use (And Why)

| Platform | Reason | Exceptions |
|----------|--------|------------|
| **Vercel** | Cost at scale, BriefHours needs more control | Static marketing sites OK |
| **AWS** | Azure commitment for BriefHours, less familiar | S3 for public assets if needed |
| **Heroku** | Expensive for production, limited features | Prototyping OK |
| **Generic Cloud PaaS** | Prefer IaaS/CaaS control or self-hosted | Unless project-specific requirement |

**Important:** These are defaults, not absolute rules. If a project has specific needs (client requirement, specialized service), exceptions are acceptable with justification.

---

## Network Architecture

### BriefHours (Azure)

```
Internet
  ↓
Azure Front Door (CDN/WAF)
  ↓
Container Apps (app tier)
  ↓ (Private Link)
PostgreSQL Flexible Server
```

**Security:**
- Managed Identity for service authentication
- Azure Key Vault for secrets
- Private networking for database access
- WAF rules for DDoS/attack protection

---

### Homelab

```
Internet
  ↓
Cloudflare Edge (DDoS protection)
  ↓
Cloudflare Tunnel (encrypted)
  ↓
Homelab (Mac Mini cluster)
  ├── Docker containers
  ├── PostgreSQL
  └── NAS (backups)
```

**Security:**
- No open inbound ports (Tunnel only)
- Cloudflare access policies
- Internal network segmentation
- Bitwarden for credential management

---

## Database Architecture

### BriefHours (Azure PostgreSQL Flexible)

**Tier:** Burstable or General Purpose (based on load)
**Backup:** Automated daily backups, 7-35 day retention
**High Availability:** Geo-redundant backup enabled
**Access:** Private endpoint only, no public IP

**Connection:**
```typescript
// Via Managed Identity
const connectionString = process.env.POSTGRESQL_CONNECTION_STRING;
// Format: postgresql://user@host:5432/dbname?sslmode=require
```

---

### Homelab (Self-hosted PostgreSQL)

**Deployment:** Docker container or native install
**Backup:** Restic to NAS (daily automated)
**Access:** Internal network only, Cloudflare Tunnel for management tools

**Connection:**
```bash
# Local connection
psql -h localhost -U postgres -d mydb

# Via Docker
docker exec -it postgres psql -U postgres
```

---

## CI/CD Pipelines

### BriefHours

**Platform:** GitHub Actions or Azure DevOps

**Pipeline:**
1. Code push → GitHub
2. Run tests, linting, build
3. Build Docker image → Azure Container Registry
4. Deploy to staging Container App
5. Run smoke tests
6. Manual approval
7. Deploy to production Container App

**Secrets:** GitHub repository secrets or Azure Key Vault

---

### Homelab Projects

**Platform:** Git hooks, simple scripts, or Jenkins (optional)

**Pipeline:**
1. Code push → GitHub
2. Webhook triggers build (if configured)
3. Build Docker image locally or on Mac Mini
4. Push to local registry or Docker Hub
5. Deploy via `docker compose up -d` or Komodo webhook

**Secrets:** Docker secrets or git-ignored env files

---

## Monitoring & Observability

### BriefHours

| Aspect | Tool | What We Monitor |
|--------|------|-----------------|
| **Application Logs** | Application Insights | Errors, warnings, request traces |
| **Metrics** | Application Insights | Request rate, latency, dependencies |
| **Alerts** | Azure Monitor | Error spike, high latency, downtime |
| **Uptime** | Azure Monitor or external | Health endpoint checks |

---

### Homelab

| Aspect | Tool | What We Monitor |
|--------|------|-----------------|
| **Container Health** | Komodo UI | Running/stopped containers |
| **Logs** | `docker logs` or Dozzle | Container stdout/stderr |
| **System Resources** | Grafana + Prometheus (optional) | CPU, memory, disk |
| **Uptime** | Healthchecks.io or UptimeRobot | Ping critical services |

---

## Disaster Recovery

### BriefHours

**RTO (Recovery Time Objective):** < 1 hour
**RPO (Recovery Point Objective):** < 15 minutes

**Procedures:**
1. **Database:** Restore from Azure automated backup
2. **Application:** Redeploy previous Container App revision
3. **Configuration:** Restore from git (infrastructure-as-code)

**Tested:** Quarterly restore drills

---

### Homelab

**RTO:** Best effort (< 4 hours)
**RPO:** Daily backups

**Procedures:**
1. **Database:** Restore from Restic backup on NAS
2. **Application:** Redeploy from git + Docker images
3. **Configuration:** Restore from git (docker-compose.yml, configs)

**Backup Locations:**
- Local NAS
- Offsite backup (Backblaze B2 or similar)

---

## Scaling Strategy

### BriefHours

**Current:** Single region (UK South)
**Horizontal Scaling:** Azure Container Apps auto-scaling (CPU/HTTP rules)
**Database Scaling:** Vertical (change tier) or read replicas if needed
**Future:** Multi-region if global expansion requires it

---

### Homelab

**Current:** Single Mac Mini or small cluster
**Scaling:** Add more Mac Minis to Docker Swarm if needed
**Limitations:** Physical hardware, power, cooling
**Overflow:** Migrate to cloud if homelab capacity exceeded

---

## Cost Management

### BriefHours (Azure)

**Budget:** Track in Azure Cost Management
**Optimization:**
- Use Burstable tier for PostgreSQL during low-traffic periods
- Container Apps scale-to-zero for non-prod environments
- Azure Reservations for predictable workloads

**Monthly Estimate:**
- Container Apps: £50-200 (depends on scale)
- PostgreSQL: £50-150 (depends on tier)
- Azure OpenAI: Pay-per-use (varies)
- Total: £150-500/month (estimated)

---

### Homelab

**Fixed Costs:**
- Electricity: ~£10-20/month (Mac Mini cluster)
- Cloudflare Tunnel: Free (or Cloudflare Zero Trust plan)
- Domain: ~£10/year

**Total:** ~£10-20/month ongoing

---

## Documentation References

| Topic | Location |
|-------|----------|
| **Homelab detailed setup** | `~/git-bnx/TKN/TKNet-Homelab-Docs/` |
| **BriefHours architecture** | Check project for `ARCHITECTURE.md` |
| **Deployment procedures** | `~/.claude/policies/DEPLOYMENT.md` |
| **Repository coupling** | `~/.claude/policies/COUPLING.md` |

---

## Infrastructure Changes

**Before making infrastructure changes:**

1. Document the change (ADR or in project's ARCHITECTURE.md)
2. Review security implications
3. Estimate cost impact (Azure) or capacity impact (homelab)
4. Test in staging/dev environment
5. Plan rollback procedure
6. Get user approval for production changes

---

## Questions?

- Deployment to these environments: See `~/.claude/policies/DEPLOYMENT.md`
- Credential management: See `~/.claude/policies/SECURITY.md`
- Homelab specifics: See `~/git-bnx/TKN/TKNet-Homelab-Docs/`
