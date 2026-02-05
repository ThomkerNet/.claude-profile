# Security Policies

**Scope:** Credential management, secrets handling, security best practices

---

## Critical Rules

1. **Never** change system passwords without explicit instruction
2. **Never** hardcode secrets in code or configuration files
3. **Always** use Bitwarden for credential storage and retrieval

---

## Credential Flow

### Development
- **Source:** Bitwarden vault (via `/bw-ref` skill)
- **Access:** `bw` CLI with operator-provided session token
- **Never commit:**
  - `.env` files (use `.env.example` for structure only)
  - `credentials.json` or similar
  - API keys, tokens, passwords in code
  - Service account files

### CI/CD
- **GitHub Actions:** Repository secrets and environment secrets
- **Azure DevOps:** Variable groups (for BriefHours)
- **Homelab:** Jenkins/GitLab with vault integration

### Runtime
- **Azure (BriefHours):**
  - Managed Identity for service-to-service auth
  - Azure Key Vault for secrets storage
  - Connection strings via environment variables

- **Homelab (Other projects):**
  - Docker secrets for containerized apps
  - Environment files (git-ignored, deployed separately)
  - Komodo secret management

---

## Bitwarden Architecture

Load `/bw-ref` for complete two-vault architecture details.

**Quick reference:**
- **Personal vault:** Development credentials, API keys
- **Work vault:** Production secrets, shared team credentials

---

## Secret Rotation Policy

| Type | Rotation Frequency | Trigger Events |
|------|-------------------|----------------|
| Production DB passwords | 90 days | Team member departure |
| API keys (external services) | On breach notification | Suspicious activity |
| Development tokens | 180 days | Major version changes |
| Service account keys | 90 days | Access pattern changes |

---

## Security Checklist

Before committing code:
- [ ] No hardcoded credentials
- [ ] `.env` in `.gitignore`
- [ ] Secrets loaded from environment variables
- [ ] No API keys in logs or error messages

Before deploying:
- [ ] Secrets configured in target environment
- [ ] Connection strings validated
- [ ] Managed identities configured (Azure)
- [ ] Least-privilege access verified

---

## Common Patterns

### Loading Secrets in Code

**Node.js/TypeScript:**
```typescript
// Good - from environment
const dbPassword = process.env.DB_PASSWORD;
if (!dbPassword) throw new Error('DB_PASSWORD not configured');

// Bad - hardcoded
const dbPassword = 'my-secret-password';  // ❌ NEVER
```

**Python:**
```python
# Good - from environment
import os
db_password = os.environ.get('DB_PASSWORD')
if not db_password:
    raise ValueError('DB_PASSWORD not configured')

# Bad - hardcoded
db_password = 'my-secret-password'  # ❌ NEVER
```

### Docker Secrets

**docker-compose.yml:**
```yaml
services:
  app:
    environment:
      - DB_PASSWORD_FILE=/run/secrets/db_password
    secrets:
      - db_password

secrets:
  db_password:
    file: ./secrets/db_password.txt  # git-ignored
```

---

## Incident Response

If credentials are accidentally committed:

1. **Immediately rotate** the exposed credential
2. **Remove from git history:**
   ```bash
   git filter-repo --path-match <file> --invert-paths
   # OR
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch <file>" \
     --prune-empty --tag-name-filter cat -- --all
   ```
3. **Force push** (if safe to do so)
4. **Audit access logs** for unauthorized usage
5. **Update incident log** in Obsidian vault

---

## Questions?

- Vault architecture: Load `/bw-ref`
- MCP server setup: Load `/profile-reference`
