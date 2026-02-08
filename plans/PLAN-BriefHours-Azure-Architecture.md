# BriefHours Azure UK South Architecture Plan

## Overview

Redesign BriefHours infrastructure for Azure UK South deployment with:
- **Zero public IPs** - All ingress via Cloudflare Tunnel (consistent with current pattern)
- **Scale-to-zero** - Container Apps with consumption-based billing
- **UK data residency** - Legal sector compliance
- **Cost targets**: Near-zero pre-launch → £25-30/mo (100 users) → £150-200/mo (500 users)

---

## Architecture Summary

```
                              INTERNET
                                  │
                   ┌──────────────┴──────────────┐
                   │      CLOUDFLARE EDGE        │
                   │  (Tunnel, DNS, WAF, CDN)    │
                   │                              │
                   │  briefhours.com → CF Pages   │
                   │  app.briefhours.com ─┐       │
                   │  api.briefhours.com ─┼──►Tunnel
                   └──────────────────────┼──────┘
                                          │
                   ═══════════════════════╪═══════════════════════
                          AZURE UK SOUTH  │  (No public IPs)
                   ═══════════════════════╪═══════════════════════
                                          │
                   ┌──────────────────────┼──────────────────────┐
                   │  VNet (10.0.0.0/16)  │                      │
                   │                      ▼                      │
                   │  ┌─────────────────────────────────────┐   │
                   │  │  Container Apps Environment          │   │
                   │  │  (Internal ingress only)             │   │
                   │  │                                       │   │
                   │  │  ┌───────────┐  ┌───────────────┐    │   │
                   │  │  │cloudflared│  │ca-briefhours- │    │   │
                   │  │  │ (tunnel)  │  │     app       │    │   │
                   │  │  └─────┬─────┘  └───────┬───────┘    │   │
                   │  │        │                │            │   │
                   │  │        │         ┌──────┴──────┐     │   │
                   │  │        │         │ca-briefhours│     │   │
                   │  │        │         │   -webapp   │     │   │
                   │  │        │         └─────────────┘     │   │
                   │  └────────┼───────────────┼─────────────┘   │
                   │           │               │                  │
                   │  ┌────────┴───────────────┴────────┐        │
                   │  │     Private Endpoints            │        │
                   │  │  ┌─────────┐ ┌─────────┐        │        │
                   │  │  │Key Vault│ │  Blob   │        │        │
                   │  │  └─────────┘ └─────────┘        │        │
                   │  └─────────────────────────────────┘        │
                   │                                              │
                   │  ┌─────────────────────────────────┐        │
                   │  │  PostgreSQL Flexible Server      │        │
                   │  │  (VNet delegated, no public IP)  │        │
                   │  └─────────────────────────────────┘        │
                   └──────────────────────────────────────────────┘
                                          │
                                          │ HTTPS (Cloudflare Tunnel)
                                          ▼
                   ┌──────────────────────────────────────────────┐
                   │  HOMELAB (Inference)                         │
                   │  Mac Minis via Cloudflare Tunnel             │
                   │  - whisper.cpp (transcription)               │
                   │  - Ollama (LLM extraction)                   │
                   │  Phase 2: Deepgram/Groq API fallback         │
                   └──────────────────────────────────────────────┘
```

---

## Key Design Decisions

### 1. No Public IPs - Cloudflare Tunnel Only

| Component | Exposure | Method |
|-----------|----------|--------|
| Container Apps | Internal only | cloudflared container in same environment |
| PostgreSQL | VNet delegated | No public endpoint |
| Key Vault | Private endpoint | No public endpoint |
| Blob Storage | Private endpoint | No public endpoint |

**cloudflared container** runs as a Container App with:
- Internal ingress to route to other apps
- Outbound connection to Cloudflare (no inbound required)
- Handles: api.briefhours.com, app.briefhours.com

### 2. Container Apps Scale-to-Zero

| Container App | Min Replicas | Max Replicas | Trigger |
|---------------|--------------|--------------|---------|
| cloudflared | 1 | 1 | Always running (tunnel) |
| ca-briefhours-app | 0 | 5 | HTTP requests |
| ca-briefhours-webapp | 0 | 3 | HTTP requests |

### 3. PostgreSQL Stoppable Pre-Launch

```bash
# Stop during pre-launch (pay only storage ~£3/mo)
az postgres flexible-server stop --name psql-briefhours-prod --resource-group briefhours-prod-uksouth-rg

# Weekly cron to prevent auto-restart (Azure restarts after 7 days)
```

### 4. Inference - External Only

| Phase | Transcription | LLM | Cost |
|-------|---------------|-----|------|
| Phase 1 | Homelab Whisper | Homelab Ollama | £0 marginal |
| Phase 2 | Deepgram API | Groq API | Pay-per-use |

---

## Resource Inventory

### Resource Group: `briefhours-prod-uksouth-rg`

| Resource | Name | SKU/Tier |
|----------|------|----------|
| VNet | vnet-briefhours-prod-uksouth | - |
| Container Apps Environment | cae-briefhours-prod | Consumption (Workload Profiles) |
| Container App | ca-cloudflared | 0.25 vCPU, 0.5Gi |
| Container App | ca-briefhours-app | 0.5 vCPU, 1Gi |
| Container App | ca-briefhours-webapp | 0.25 vCPU, 0.5Gi |
| PostgreSQL Flexible | psql-briefhours-prod | B1ms (stoppable) → D2s_v3 |
| Key Vault | kv-briefhours-prod | Standard |
| Storage Account | stbriefhoursprod | Standard LRS |
| Log Analytics | log-briefhours-prod | PerGB2018 |
| Managed Identity | id-briefhours-app | User-assigned |
| Managed Identity | id-briefhours-webapp | User-assigned |

### Networking

| Subnet | CIDR | Purpose |
|--------|------|---------|
| snet-aca | 10.0.0.0/23 | Container Apps (delegated) |
| snet-postgres | 10.0.2.0/28 | PostgreSQL (delegated) |
| snet-private-endpoints | 10.0.3.0/28 | Key Vault, Blob PE |

### Private DNS Zones

- privatelink.postgres.database.azure.com
- privatelink.vaultcore.azure.net
- privatelink.blob.core.windows.net

---

## Cost Breakdown

### Pre-Launch (Target: Near-Zero)

| Resource | Config | £/month |
|----------|--------|---------|
| Container Apps | cloudflared only (~730 hrs × 0.25 vCPU) | ~3 |
| PostgreSQL | **STOPPED** (32GB storage only) | ~3 |
| Key Vault | Standard, <10 secrets | <1 |
| Storage | LRS, <1GB | <1 |
| Log Analytics | Free tier (5GB) | 0 |
| Private DNS | 3 zones | ~1 |
| **TOTAL** | | **~8-10** |

### 100 Users (Target: £25-30/mo)

| Resource | Config | £/month |
|----------|--------|---------|
| Container Apps | ~100 vCPU-hours | ~8 |
| PostgreSQL | B2s running | ~18 |
| Key Vault | Standard | <1 |
| Storage | <10GB | <1 |
| Log Analytics | ~5GB | ~5 |
| **TOTAL** | | **~32-35** |

*Slightly over target - can reduce Log Analytics retention*

### 500 Users (Target: £150-200/mo)

| Resource | Config | £/month |
|----------|--------|---------|
| Container Apps | ~400 vCPU-hours | ~35 |
| PostgreSQL | D2s_v3 (GP) | ~90 |
| Key Vault | Standard | ~1 |
| Storage | <50GB | ~2 |
| Log Analytics | ~30GB | ~35 |
| App Insights | Included | ~10 |
| **TOTAL** | | **~175** |

---

## Terraform Repository

**New repo:** `BriefHours-TFAzure-Infra`

```
BriefHours-TFAzure-Infra/
├── CLAUDE.md                 # Instructions for Terraform agent
├── environments/
│   └── prod/
│       ├── main.tf           # Root module
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfvars
│       └── backend.tf        # Azure Storage backend
│
├── modules/
│   ├── networking/           # VNet, subnets, NSGs, private DNS
│   ├── identity/             # Managed identities, RBAC
│   ├── keyvault/             # Key Vault, private endpoint
│   ├── storage/              # Blob storage, lifecycle, private endpoint
│   ├── database/             # PostgreSQL Flexible, VNet integration
│   ├── container-apps/       # Environment, apps, secrets
│   └── monitoring/           # Log Analytics, App Insights, alerts
│
├── scripts/
│   ├── init-secrets.sh       # Populate Key Vault secrets
│   ├── stop-postgres.sh      # Cost optimization
│   └── start-postgres.sh
│
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml
│       └── terraform-apply.yml
│
└── README.md
```

### Module Dependency Order

1. `networking` - VNet, subnets, DNS zones
2. `identity` - Managed identities
3. `keyvault` - Key Vault + private endpoint
4. `storage` - Blob storage + private endpoint
5. `database` - PostgreSQL + VNet delegation
6. `monitoring` - Log Analytics, App Insights
7. `container-apps` - Environment + all apps

---

## Documentation Updates Required

### Files to Update

| File | Changes |
|------|---------|
| `infrastructure/DEPLOYMENT_TOPOLOGY.md` | Add Azure section alongside existing homelab |
| `infrastructure/AZURE_DEPLOYMENT.md` | **NEW** - Azure-specific deployment guide |
| `infrastructure/NETWORKING.md` | Add Azure VNet + Cloudflare Tunnel pattern |
| `infrastructure/SECRETS_MANAGEMENT.md` | Add Key Vault section |
| `specs/BRIEFHOURS_INFERENCE_SPEC.md` | Add Deepgram/Groq fallback APIs |
| `ARCHITECTURE_OVERVIEW.md` | Add Azure deployment option |

### New Files to Create

| File | Purpose |
|------|---------|
| `infrastructure/AZURE_DEPLOYMENT.md` | Complete Azure deployment guide |
| `infrastructure/AZURE_COST_OPTIMIZATION.md` | Cost management strategies |
| `decisions/ADR-005-AZURE-DEPLOYMENT.md` | Decision record for Azure migration |

---

## Terraform Handoff Spec

### For Claude Terraform Agent

**Objective:** Create Terraform modules to deploy BriefHours on Azure UK South

**Constraints:**
1. **Zero public IPs** - All ingress via Cloudflare Tunnel
2. **UK South region only** - Data residency requirement
3. **Managed Identity everywhere** - No hardcoded credentials
4. **VNet isolation** - Private endpoints for all PaaS services
5. **Scale-to-zero** - Container Apps consumption model
6. **Stoppable database** - PostgreSQL Flexible Server (can be stopped)

**Key Implementation Details:**

1. **cloudflared Container App:**
   ```hcl
   # Must run continuously (min_replicas = 1)
   # Image: cloudflare/cloudflared:latest
   # Command: tunnel --no-autoupdate run --token ${TUNNEL_TOKEN}
   # Internal ingress only
   ```

2. **Container Apps Environment:**
   ```hcl
   # internal_load_balancer_enabled = true
   # No external ingress
   # Workload profiles with Consumption tier
   ```

3. **PostgreSQL:**
   ```hcl
   # delegated_subnet_id for VNet integration
   # public_network_access_enabled = false
   # No HA initially (cost)
   ```

4. **Key Vault Secrets Reference:**
   ```hcl
   # Container Apps reference secrets via:
   # key_vault_secret_id + identity
   ```

**Deliverables:**
1. All Terraform modules in `modules/` directory
2. Production environment config in `environments/prod/`
3. GitHub Actions workflow for plan/apply
4. README with usage instructions

---

## Implementation Sequence

### Phase 1: Infrastructure (Terraform)
1. Create Azure resource group
2. Deploy networking (VNet, subnets, DNS zones)
3. Deploy managed identities
4. Deploy Key Vault + private endpoint
5. Deploy storage + private endpoint
6. Deploy PostgreSQL (stopped initially)
7. Deploy Log Analytics
8. Deploy Container Apps environment
9. Deploy cloudflared container
10. Configure Cloudflare Tunnel routes

### Phase 2: Application Deployment
1. Build and push container images to ACR (or GitHub Container Registry)
2. Deploy ca-briefhours-app
3. Deploy ca-briefhours-webapp
4. Configure custom domains in Cloudflare
5. Test end-to-end flow

### Phase 3: Documentation
1. Update architecture docs
2. Create ADR for Azure decision
3. Update deployment runbooks

---

## Security Checklist

- [ ] No public IPs on any Azure resource
- [ ] All PaaS services use private endpoints
- [ ] PostgreSQL VNet-delegated (no public access)
- [ ] Key Vault private endpoint only
- [ ] Managed Identity for all service-to-service auth
- [ ] All secrets in Key Vault (none in code/config)
- [ ] Audit logging enabled on all resources
- [ ] UK South region for all resources
- [ ] TLS 1.2+ enforced everywhere
- [ ] Network security groups on all subnets
- [ ] Container image vulnerability scanning (Trivy/Defender)
- [ ] Cloudflare WAF with OWASP rules enabled

---

## Peer Review Findings (Gemini)

### Critical Fixes Required

1. **VNet Links for Private DNS Zones** - Must create VNet Links between VNet and each private DNS zone (postgres, keyvault, blob) - add to networking module

2. **Administrative Access** - No path for operators with zero public IPs
   - **Solution:** Add Azure Bastion in dedicated subnet for secure admin access
   - Or use `az containerapp exec` via Azure CLI with AAD auth

3. **NSG Rules Must Be Explicit:**
   - `snet-aca`: Allow egress to postgres (5432), private endpoints (443), internet only
   - `snet-postgres`: Allow ingress from snet-aca on 5432 only

4. **Secrets Bootstrapping** - Avoid `init-secrets.sh` script
   - Use GitHub Actions OIDC + federated credentials
   - Terraform populates Key Vault from GitHub secrets directly

### Cost Corrections

| Item | Plan Estimate | Corrected |
|------|---------------|-----------|
| Pre-launch Container Apps | ~£3 | **£0** (free tier covers cloudflared) |
| Pre-launch TOTAL | ~£8-10 | **~£5** |

### Additional Considerations

- **Private Endpoint data processing** has small per-GB charge (~£1-2/mo at scale)
- **Key Vault transactions** - ensure apps cache secrets at startup, not per-request
- **PostgreSQL auto-restart** (7 days) - monitoring needed for weekly stop script
- **Container image scanning** - integrate Trivy into CI/CD pipeline
