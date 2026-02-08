> **ARCHIVED:** This spec was superseded by the simplified `/bwdangerunlock` approach (2026-02-08). The two-tier scoped collection model was never implemented. See `skills/bwdangerunlock/SKILL.md` for current approach.

# SPEC: Vaultwarden Access Refactor

**Status:** Archived (never implemented)
**Priority:** High
**Created:** 2026-01-05
**Architecture Doc:** `/Users/sbarker/git-bnx/BNX-Docs-Architecture/infrastructure/VAULTWARDEN_ACCESS.md`
**ADR:** `/Users/sbarker/git-bnx/BNX-Docs-Architecture/decisions/ADR-003-VAULTWARDEN-CREDENTIAL-ACCESS.md`

## Summary

Refactor Claude's Vaultwarden access from Telegram-approval-per-request to a two-tier model:
1. **Autonomous (RO):** Claude accesses read-only collections freely
2. **Elevated (RW):** User passes time-limited session for write operations

## Goals

- Remove Telegram approval (too clunky)
- Implement structural security via Vaultwarden collections
- Store Claude's service account key securely (macOS Keychain, not file)
- Create `bw-elevate` wrapper for secure RW session handoff
- Maintain audit logging

## Non-Goals

- Setting up the Vaultwarden server itself (already exists)
- Creating the Vaultwarden accounts (manual admin task)
- Migrating existing credentials to collections (manual curation)

## Prerequisites (Manual Steps by User)

Before implementation, user must:

1. **Create Claude service account in Vaultwarden**
   - Account: `claude@boroughnexus.com`
   - Generate API key for this account

2. **Create collections in Vaultwarden**
   - `bnx-readonly` — assign to Claude account
   - `briefhours-readonly` — assign to Claude account
   - `bnx-infra` — simon@ only
   - `bnx-secrets` — simon@ only
   - `briefhours-deploy` — simon@ only

3. **Curate credentials into collections**
   - Move/copy appropriate items to RO vs RW collections
   - Apply RO criteria: only technically read-only credentials

## Implementation Tasks

### 1. Remove Telegram Approval Integration

**File:** `~/.claude/tools/vaultwarden/bw-wrapper.ts`

**Changes:**
- Remove `APPROVAL_ENABLED`, `APPROVAL_TIMEOUT`, `APPROVAL_MODULE` constants
- Remove `requestVaultApproval()` function
- Remove approval calls from `apiSearch()`, `apiGet()`, `apiCreate()`, `apiUpdate()`
- Keep audit logging (just remove approval gate)

### 2. Implement macOS Keychain Storage

**File:** `~/.claude/tools/vaultwarden/bw-wrapper.ts`

**New functions:**
```typescript
async function getKeychainCredentials(): Promise<VaultSecrets> {
  // Read from macOS Keychain using `security` CLI
  // security find-generic-password -a "claude@boroughnexus.com" -s "vaultwarden-api" -w
  // Also need client_id stored separately or as JSON blob
}

async function setKeychainCredentials(secrets: VaultSecrets): Promise<void> {
  // Store to macOS Keychain
  // security add-generic-password -a "claude@boroughnexus.com" -s "vaultwarden-api" -w "$JSON_BLOB" -U
}
```

**Changes to `loadVaultSecrets()`:**
- Try Keychain first
- Fall back to file (with deprecation warning)
- Never store master password in Keychain (only API key credentials)

### 3. Create bw-elevate Script

**New file:** `~/.claude/tools/vaultwarden/bw-elevate.ts`

**Purpose:** Secure wrapper for granting Claude time-limited RW access

**Interface:**
```bash
bw-elevate --collection <name> --reason "Reason for access" [--ttl 30]
```

**Workflow:**
1. Parse args (collection, reason, ttl)
2. Prompt for master password (stdin, not echoed)
3. Run `bw unlock --passwordenv BW_PASSWORD --raw`
4. Log to audit: timestamp, collection, reason, operator (from `whoami`)
5. Output session key to stdout (for piping to Claude)
6. Optionally: set timer to auto-lock after TTL

**Security requirements:**
- Password input via stdin with echo disabled
- Session key output to stdout only (not logged)
- Reason is mandatory
- Audit log entry before session key output

### 4. Create bw-elevate Command

**New file:** `~/.claude/commands/bw-elevate.md`

**Content:**
```markdown
Elevate Claude's Vaultwarden access to a RW collection.

Usage: /bw-elevate <collection> <reason>

Example: /bw-elevate briefhours-deploy "Deploying webapp v1.2.3"
```

### 5. Update Vault Commands

**Files to update:**
- `~/.claude/commands/vault.md` — update help text
- `~/.claude/commands/vault-start.template.md` — remove or deprecate
- `~/.claude/commands/vault-get.template.md` — keep as-is (RO access)
- `~/.claude/commands/vault-search.template.md` — keep as-is (RO access)

**New behavior:**
- `/vault-get` and `/vault-search` work autonomously (no approval)
- `/bw-elevate` required for RW operations
- `/vault-start` deprecated (auto-start handles this)

### 6. Update Audit Logging

**File:** `~/.claude/tools/vaultwarden/bw-wrapper.ts`

**Add new log events:**
```typescript
interface AuditEntry {
  timestamp: string;
  action: 'ro-access' | 'rw-session-start' | 'rw-access' | 'session-expired';
  collection?: string;
  item?: string;
  reason?: string;
  operator?: string;
  sessionId?: string;
  result: 'success' | 'denied' | 'error';
}
```

### 7. Setup Command for Initial Configuration

**New file:** `~/.claude/tools/vaultwarden/setup-keychain.ts`

**Purpose:** One-time setup to store credentials in Keychain

**Usage:**
```bash
bun run setup-keychain.ts
# Prompts for:
# - Vaultwarden server URL
# - Client ID
# - Client Secret
# Stores in macOS Keychain
```

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `bw-wrapper.ts` | Modify | Remove Telegram approval, add Keychain support |
| `bw-elevate.ts` | Create | New secure RW session wrapper |
| `setup-keychain.ts` | Create | One-time Keychain setup |
| `vault.md` | Modify | Update help text |
| `vault-start.template.md` | Deprecate | No longer needed (auto-start) |
| `bw-elevate.md` | Create | New command for RW elevation |

## Testing Checklist

- [ ] RO access works without any approval
- [ ] RO access fails for RW collections (403 from Vaultwarden)
- [ ] Keychain storage works on macOS
- [ ] Keychain retrieval works
- [ ] `bw-elevate` prompts for password securely
- [ ] `bw-elevate` requires --reason
- [ ] Session key passed via stdout, not logged
- [ ] Audit log captures all access
- [ ] TTL expiry works correctly
- [ ] Graceful fallback if Keychain unavailable

## Security Considerations

1. **Never log session keys** — stdout only, not in audit log
2. **Never log passwords** — input with echo disabled
3. **Keychain ACL** — consider restricting to specific apps
4. **Audit log permissions** — 0600, not world-readable
5. **Reason required** — cannot elevate without stating purpose

## Rollback Plan

If issues arise:
1. Restore `vault-secrets.json` file approach
2. Re-enable Telegram approval (set `VAULT_APPROVAL_ENABLED=true`)
3. Original code preserved in git history

## Related Documentation

- Architecture: `/Users/sbarker/git-bnx/BNX-Docs-Architecture/infrastructure/VAULTWARDEN_ACCESS.md`
- ADR: `/Users/sbarker/git-bnx/BNX-Docs-Architecture/decisions/ADR-003-VAULTWARDEN-CREDENTIAL-ACCESS.md`
- Obsidian: `Projects/BoroughNexus/AI-Claude/Bitwarden Scoped Access for Claude.md`

## AI Peer Review Summary

Reviewed by GPT-5.1 and Gemini-3-Pro (2026-01-05):

**Consensus:**
- Two-tier model is sound
- Keychain storage critical (not plain file)
- Session handoff via stdin (not command-line args)
- Audit logging must replace Telegram visibility

**Key recommendations incorporated:**
- Technical RO enforcement (not just naming)
- `--reason` requirement for audit trail
- Auto-lock/TTL for elevated sessions
