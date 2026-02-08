# Plan: Test Site with Cloudflare Access Protection

## Goal
Deploy `test` branch of briefhours-web to `test.briefhours.com` and `www.test.briefhours.com`, protected by Cloudflare Access with social login (Google/GitHub), allowing only whitelisted emails.

## Architecture

```
test branch → GitHub Actions → Cloudflare Pages (test.briefhours-web.pages.dev)
                                        ↓
                              DNS CNAME → test.briefhours.com
                                        ↓
                              Cloudflare Access (social login gate)
                                        ↓
                              Authorized users only
```

## Implementation Steps

### Step 1: Create `test` branch in briefhours-web repo
```bash
cd ~/git-bnx/briefhours-web
git checkout -b test
git push -u origin test
```

### Step 2: Update GitHub Actions workflow for multi-branch deploy
Edit `.github/workflows/deploy.yml` to deploy both `main` and `test` branches:
- `main` → production
- `test` → preview (uses branch alias)

### Step 3: Add custom domains for test branch via API
Create DNS CNAME records pointing to the test branch alias:
- `test.briefhours.com` → `test.briefhours-web.pages.dev`
- `www.test` → `test.briefhours-web.pages.dev`

Add custom domains to Pages project via API.

### Step 4: Get Cloudflare Access team name
Check existing Zero Trust configuration to get team domain name for OAuth callbacks.

### Step 5: Create OAuth apps for identity providers

**GitHub OAuth App:**
- Homepage URL: `https://<team>.cloudflareaccess.com`
- Callback URL: `https://<team>.cloudflareaccess.com/cdn-cgi/access/callback`

**Google OAuth App:**
- Authorized origins: `https://<team>.cloudflareaccess.com`
- Redirect URI: `https://<team>.cloudflareaccess.com/cdn-cgi/access/callback`

### Step 6: Configure identity providers in Cloudflare One
Add GitHub and Google as identity providers via API:
```
POST /accounts/{account_id}/access/identity_providers
```

### Step 7: Create Access application for test domains
```
POST /accounts/{account_id}/access/apps
```
- Type: self_hosted
- Domain: test.briefhours.com
- Session duration: 24h (or as preferred)

### Step 8: Create Access policy (whitelist specific emails)
```
POST /accounts/{account_id}/access/apps/{app_id}/policies
```
- Action: allow
- Include: emails (list of authorized emails)

### Step 9: Store credentials in Bitwarden
Save OAuth client IDs/secrets for future reference.

### Step 10: Update documentation
Add test site configuration to CLAUDE.md.

## API Endpoints Reference

| Action | Endpoint |
|--------|----------|
| Add custom domain | `POST /accounts/{id}/pages/projects/{name}/domains` |
| Create DNS record | `POST /zones/{id}/dns_records` |
| Add identity provider | `POST /accounts/{id}/access/identity_providers` |
| Create Access app | `POST /accounts/{id}/access/apps` |
| Create Access policy | `POST /accounts/{id}/access/apps/{app_id}/policies` |

## Files to Modify

1. `~/git-bnx/briefhours-web/.github/workflows/deploy.yml` - Add test branch trigger
2. `~/git-bnx/BriefHours-Deploy/CLAUDE.md` - Document test site setup

## Prerequisites (Already Available)

- Existing OAuth apps configured in Cloudflare One (GitHub/Google)
- Will need: List of authorized email addresses for access policy

## Simplified Flow (Using Existing IdPs)

Since identity providers are already configured in Cloudflare One, Steps 5-6 are simplified to just referencing existing IdPs when creating the Access application.
