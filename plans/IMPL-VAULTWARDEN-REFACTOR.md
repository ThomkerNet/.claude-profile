# Implementation Plan: Vaultwarden Access Refactor (v2)

**Spec Reference:** `plans/SPEC-VAULTWARDEN-ACCESS-REFACTOR.md`
**Date:** 2026-01-05
**Status:** Revised after AI Peer Review
**Reviewers:** GPT-5.1, Gemini-3-Pro-Preview

---

## Revision Summary

Key changes from v1 based on peer review:

1. **Master password stored in Keychain** — Required for vault decryption (bw CLI cannot decrypt without it)
2. **`bw-elevate` is user-only** — Agent instructs user to run in terminal, never runs it itself
3. **Wrapper reads elevated session file** — Added logic to check `.bw-elevated-session`
4. **RO/RW separation is structural** — Enforced by Vaultwarden collection assignments, not wrapper code
5. **Fixed code quality issues** — Async handling, duplicate constants, proper cleanup

---

## Executive Summary

Refactor Claude's Vaultwarden access from Telegram-approval-per-request to a two-tier model:
- **Tier 1 (RO):** Autonomous read access via API credentials + master password in Keychain
- **Tier 2 (RW):** User-elevated session for write operations (user runs `bw-elevate` manually)

**Security model:** Collection-level access control in Vaultwarden (structural), not code-enforced.

---

## Phase 1: Remove Telegram Approval (30 min)

### Task 1.1: Modify `bw-wrapper.ts` - Remove Approval Gates

**File:** `~/.claude/tools/vaultwarden/bw-wrapper.ts`

**Lines to remove/modify:**
- Lines 47-50: Delete `APPROVAL_MODULE`, `APPROVAL_ENABLED`, `APPROVAL_TIMEOUT` constants
- Lines 387-450: Delete entire `requestVaultApproval()` function
- Lines 452-458: In `apiSearch()`, remove approval check block
- Lines 480-486: In `apiGet()`, remove approval check block
- Lines 528-538: In `apiCreate()`, remove approval check block
- Lines 578-585: In `apiUpdate()`, remove approval check block

**Keep intact:**
- `auditLog()` function and all audit log calls
- All other functionality

---

## Phase 2: Implement macOS Keychain Storage (60 min)

### Task 2.1: Create Shared Constants Module

**New file:** `~/.claude/tools/vaultwarden/constants.ts`

```typescript
/**
 * Shared constants for Vaultwarden tools.
 * Single source of truth to avoid duplication.
 */

import { homedir } from "os";
import { join } from "path";

// Keychain identifiers
export const KEYCHAIN_SERVICE = "vaultwarden-claude";
export const KEYCHAIN_ACCOUNT = "api-credentials";

// File paths
export const TOOLS_DIR = join(homedir(), ".claude", "tools", "vaultwarden");
export const SESSION_FILE = join(TOOLS_DIR, ".bw-session");
export const PID_FILE = join(TOOLS_DIR, ".bw-serve.pid");
export const TTL_FILE = join(TOOLS_DIR, ".bw-serve.ttl");
export const ELEVATED_SESSION_FILE = join(TOOLS_DIR, ".bw-elevated-session");
export const ELEVATED_TTL_FILE = join(TOOLS_DIR, ".bw-elevated.ttl");
export const AUDIT_LOG = join(TOOLS_DIR, "audit.log");
export const SECRETS_FILE = join(TOOLS_DIR, "vault-secrets.json");

// Server config
export const VAULTWARDEN_URL = process.env.BW_SERVER || "https://vaultwarden.thomker.net";
export const API_PORT = 8087;
export const API_BASE = `http://localhost:${API_PORT}`;
export const DEFAULT_TTL_MINUTES = 30;

// Platform
export const IS_WINDOWS = process.platform === "win32";
export const BW_CMD = IS_WINDOWS ? "bw.cmd" : "bw";

// Valid RW collections (must match Vaultwarden setup)
export const RW_COLLECTIONS = [
  "bnx-infra",
  "bnx-secrets",
  "briefhours-deploy",
];
```

### Task 2.2: Create Keychain Helper Module

**New file:** `~/.claude/tools/vaultwarden/keychain.ts`

```typescript
/**
 * macOS Keychain helpers for credential storage.
 */

import { $ } from "bun";
import { KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT } from "./constants";

export interface KeychainCredentials {
  server_url: string;
  client_id: string;
  client_secret: string;
  master_password: string;  // Required for vault decryption
}

export async function getKeychainCredentials(): Promise<KeychainCredentials | null> {
  try {
    const result = await $`security find-generic-password -s ${KEYCHAIN_SERVICE} -a ${KEYCHAIN_ACCOUNT} -w`.quiet().text();
    const parsed = JSON.parse(result.trim());

    // Validate required fields
    if (!parsed.client_id || !parsed.client_secret || !parsed.master_password) {
      console.error("Keychain credentials incomplete. Run setup-keychain.ts");
      return null;
    }

    return parsed as KeychainCredentials;
  } catch {
    return null;
  }
}

export async function setKeychainCredentials(creds: KeychainCredentials): Promise<void> {
  const json = JSON.stringify(creds);
  // -U flag updates if exists, creates if not
  await $`security add-generic-password -s ${KEYCHAIN_SERVICE} -a ${KEYCHAIN_ACCOUNT} -w ${json} -U`.quiet();
}

export async function deleteKeychainCredentials(): Promise<void> {
  try {
    await $`security delete-generic-password -s ${KEYCHAIN_SERVICE} -a ${KEYCHAIN_ACCOUNT}`.quiet();
  } catch {
    // Ignore if not found
  }
}
```

### Task 2.3: Modify `loadVaultSecrets()` in `bw-wrapper.ts`

**Replace lines 75-102 with:**

```typescript
import { getKeychainCredentials } from "./keychain";
import { SECRETS_FILE } from "./constants";

/**
 * Load vault secrets from Keychain (preferred) or file (deprecated fallback).
 * Now async to support Keychain access.
 */
async function loadVaultSecrets(): Promise<VaultSecrets> {
  // Try Keychain first (preferred, includes master password)
  const keychainCreds = await getKeychainCredentials();

  if (keychainCreds) {
    return {
      client_id: keychainCreds.client_id,
      client_secret: keychainCreds.client_secret,
      master_password: keychainCreds.master_password,
    };
  }

  // Fall back to file (deprecated, with warning)
  if (existsSync(SECRETS_FILE)) {
    console.warn("Warning: Using file-based secrets (deprecated). Run setup-keychain.ts to migrate.");
    try {
      const secrets = JSON.parse(readFileSync(SECRETS_FILE, "utf-8")) as VaultSecrets;
      if (!secrets.client_id || !secrets.client_secret || !secrets.master_password) {
        console.error("Vault secrets file incomplete.");
        console.error("Required fields: client_id, client_secret, master_password");
        process.exit(1);
      }
      return secrets;
    } catch (error: any) {
      console.error("Failed to parse vault secrets:", error.message);
      process.exit(1);
    }
  }

  console.error("No vault credentials found.");
  console.error("Run: bun run setup-keychain.ts");
  process.exit(1);
}
```

### Task 2.4: Update All Callers of `loadVaultSecrets()`

**In `bw-wrapper.ts`, update these locations:**

- Line 128: `const secrets = loadVaultSecrets();` → `const secrets = await loadVaultSecrets();`
- Ensure `ensureUnlocked()` remains async (it already is)

### Task 2.5: Create `setup-keychain.ts`

**New file:** `~/.claude/tools/vaultwarden/setup-keychain.ts`

```typescript
#!/usr/bin/env bun
/**
 * One-time setup to store Vaultwarden credentials in macOS Keychain.
 *
 * Stores: server URL, client ID, client secret, AND master password.
 * Master password is required for vault decryption.
 *
 * Usage:
 *   bun run setup-keychain.ts
 */

import { $ } from "bun";
import * as readline from "readline";
import { KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT, VAULTWARDEN_URL } from "./constants";
import { setKeychainCredentials, getKeychainCredentials, KeychainCredentials } from "./keychain";

async function prompt(question: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

async function promptHidden(question: string): Promise<string> {
  process.stdout.write(question);

  // Disable echo
  await $`stty -echo`.quiet();

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false,
  });

  return new Promise((resolve) => {
    rl.once("line", async (answer) => {
      rl.close();
      await $`stty echo`.quiet();
      console.log(); // Newline after hidden input
      resolve(answer.trim());
    });
  });
}

async function main() {
  console.log("=== Vaultwarden Keychain Setup ===\n");
  console.log("This stores your credentials securely in macOS Keychain.");
  console.log("Master password IS stored (required for vault decryption).\n");

  // Check for existing credentials
  const existing = await getKeychainCredentials();
  if (existing) {
    const overwrite = await prompt("Existing credentials found. Overwrite? (y/N): ");
    if (overwrite.toLowerCase() !== "y") {
      console.log("Aborted.");
      process.exit(0);
    }
  }

  console.log("\nGet your API key from:");
  console.log("  Vaultwarden Web -> Settings -> Security -> Keys -> View API Key\n");

  const serverUrl = await prompt(`Vaultwarden URL [${VAULTWARDEN_URL}]: `);
  const clientId = await prompt("Client ID: ");
  const clientSecret = await promptHidden("Client Secret: ");
  const masterPassword = await promptHidden("Master Password: ");

  if (!clientId || !clientSecret || !masterPassword) {
    console.error("\nAll fields are required.");
    process.exit(1);
  }

  const creds: KeychainCredentials = {
    server_url: serverUrl || VAULTWARDEN_URL,
    client_id: clientId,
    client_secret: clientSecret,
    master_password: masterPassword,
  };

  await setKeychainCredentials(creds);

  console.log("\n✓ Credentials stored in macOS Keychain");
  console.log(`  Service: ${KEYCHAIN_SERVICE}`);
  console.log(`  Account: ${KEYCHAIN_ACCOUNT}`);
  console.log("\nClaude can now access the vault autonomously.");
  console.log("For RW operations, run bw-elevate manually when needed.\n");
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
```

---

## Phase 3: Create `bw-elevate` Script (45 min)

**Important:** This script is run by the USER manually, NOT by the agent. The agent instructs the user to run it.

### Task 3.1: Create `bw-elevate.ts`

**New file:** `~/.claude/tools/vaultwarden/bw-elevate.ts`

```typescript
#!/usr/bin/env bun
/**
 * Secure RW session elevation for Vaultwarden access.
 *
 * IMPORTANT: This script is run by the USER in their terminal,
 * NOT by the Claude agent. This prevents password exposure in chat.
 *
 * Usage:
 *   bun run bw-elevate.ts --collection <name> --reason "Reason"
 *
 * The elevated session is written to a file that bw-wrapper.ts reads.
 */

import { $ } from "bun";
import { appendFileSync, writeFileSync } from "fs";
import * as readline from "readline";
import {
  VAULTWARDEN_URL,
  BW_CMD,
  ELEVATED_SESSION_FILE,
  ELEVATED_TTL_FILE,
  AUDIT_LOG,
  RW_COLLECTIONS,
  DEFAULT_TTL_MINUTES,
  SESSION_FILE,
} from "./constants";

async function promptHidden(question: string): Promise<string> {
  process.stdout.write(question);
  await $`stty -echo`.quiet();

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false,
  });

  return new Promise((resolve) => {
    rl.once("line", async (answer) => {
      rl.close();
      await $`stty echo`.quiet();
      console.log();
      resolve(answer.trim());
    });
  });
}

function auditLog(entry: Record<string, any>): void {
  const fullEntry = {
    timestamp: new Date().toISOString(),
    ...entry,
  };
  try {
    appendFileSync(AUDIT_LOG, JSON.stringify(fullEntry) + "\n", { mode: 0o600 });
  } catch {
    // Silently fail
  }
}

async function getOperator(): Promise<string> {
  try {
    return (await $`whoami`.quiet().text()).trim();
  } catch {
    return "unknown";
  }
}

function parseArgs(args: string[]): { collection: string; reason: string; ttl: number } {
  let collection = "";
  let reason = "";
  let ttl = DEFAULT_TTL_MINUTES;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--collection" && args[i + 1]) {
      collection = args[++i];
    } else if (arg === "--reason" && args[i + 1]) {
      reason = args[++i];
    } else if (arg === "--ttl" && args[i + 1]) {
      ttl = parseInt(args[++i]);
    } else if (arg.startsWith("--collection=")) {
      collection = arg.slice(13);
    } else if (arg.startsWith("--reason=")) {
      reason = arg.slice(9);
    } else if (arg.startsWith("--ttl=")) {
      ttl = parseInt(arg.slice(6));
    }
  }

  return { collection, reason, ttl };
}

async function main() {
  const args = process.argv.slice(2);

  if (args.includes("--help") || args.includes("-h")) {
    console.log(`
bw-elevate: Elevate Vaultwarden access for RW operations

IMPORTANT: Run this in YOUR terminal, not via Claude.

Usage:
  bun run bw-elevate.ts --collection <name> --reason "Reason" [--ttl 30]

Collections:
  ${RW_COLLECTIONS.join(", ")}

Example:
  bun run bw-elevate.ts --collection briefhours-deploy --reason "Deploy v1.2.3"
`);
    process.exit(0);
  }

  const { collection, reason, ttl } = parseArgs(args);

  if (!collection) {
    console.error("Error: --collection is required");
    process.exit(1);
  }

  if (!reason) {
    console.error("Error: --reason is required (for audit trail)");
    process.exit(1);
  }

  if (!RW_COLLECTIONS.includes(collection)) {
    console.error(`Error: Invalid collection: ${collection}`);
    console.error(`Valid: ${RW_COLLECTIONS.join(", ")}`);
    process.exit(1);
  }

  if (isNaN(ttl) || ttl < 1 || ttl > 480) {
    console.error("Error: TTL must be between 1 and 480 minutes");
    process.exit(1);
  }

  const operator = await getOperator();

  console.log(`\nElevating access to: ${collection}`);
  console.log(`Reason: ${reason}`);
  console.log(`TTL: ${ttl} minutes\n`);

  const password = await promptHidden("Master Password: ");

  if (!password) {
    console.error("Error: Password is required");
    auditLog({
      action: "rw-session-start",
      collection,
      reason,
      operator,
      result: "error_no_password",
    });
    process.exit(1);
  }

  console.log("Unlocking vault...");

  try {
    const unlockResult = await $`${BW_CMD} unlock --passwordenv BW_PASSWORD --raw`.env({
      ...process.env as Record<string, string>,
      BW_SERVER: VAULTWARDEN_URL,
      BW_PASSWORD: password,
    }).text();

    const session = unlockResult.trim();

    if (!session) {
      throw new Error("No session key returned");
    }

    const sessionId = `elev-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const expiryTime = Date.now() + (ttl * 60 * 1000);

    // Log BEFORE writing session
    auditLog({
      action: "rw-session-start",
      collection,
      reason,
      operator,
      sessionId,
      result: "success",
    });

    // Write elevated session info (bw-wrapper.ts reads this)
    writeFileSync(ELEVATED_SESSION_FILE, JSON.stringify({
      sessionId,
      session,  // The actual BW session key
      collection,
      reason,
      expiryTime,
      operator,
    }), { mode: 0o600 });

    writeFileSync(ELEVATED_TTL_FILE, String(expiryTime), { mode: 0o600 });

    // Also update the main session file (so bw serve uses it)
    writeFileSync(SESSION_FILE, session, { mode: 0o600 });

    console.log(`\n✓ Elevated session granted`);
    console.log(`  Session ID: ${sessionId}`);
    console.log(`  Collection: ${collection}`);
    console.log(`  Expires: ${new Date(expiryTime).toLocaleTimeString()}`);
    console.log(`\nClaude can now perform RW operations on ${collection}.`);

  } catch (error: any) {
    auditLog({
      action: "rw-session-start",
      collection,
      reason,
      operator,
      result: "error_unlock_failed",
    });
    console.error("Failed to unlock vault:", error.message);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
```

### Task 3.2: Update `bw-wrapper.ts` to Check Elevated Session

**Add after existing session functions (around line 260):**

```typescript
import { ELEVATED_SESSION_FILE, ELEVATED_TTL_FILE } from "./constants";

interface ElevatedSession {
  sessionId: string;
  session: string;
  collection: string;
  reason: string;
  expiryTime: number;
  operator: string;
}

function getElevatedSession(): ElevatedSession | null {
  if (!existsSync(ELEVATED_SESSION_FILE)) {
    return null;
  }

  try {
    const data = JSON.parse(readFileSync(ELEVATED_SESSION_FILE, "utf-8"));

    // Check if expired
    if (Date.now() > data.expiryTime) {
      // Clean up expired session
      try {
        const { unlinkSync } = require("fs");
        unlinkSync(ELEVATED_SESSION_FILE);
        unlinkSync(ELEVATED_TTL_FILE);
      } catch {}

      auditLog("session_expired", data.collection, "expired");
      return null;
    }

    return data as ElevatedSession;
  } catch {
    return null;
  }
}

function isElevatedFor(collection: string): boolean {
  const elevated = getElevatedSession();
  if (!elevated) return false;
  return elevated.collection === collection;
}
```

**Modify `apiCreate()` and `apiUpdate()` to check elevation:**

```typescript
async function apiCreate(options: CreateItemOptions): Promise<void> {
  // Check for elevated session (required for create)
  const elevated = getElevatedSession();
  if (!elevated) {
    console.error("RW operation requires elevated session.");
    console.error("Please run in your terminal:");
    console.error("  bun run ~/.claude/tools/vaultwarden/bw-elevate.ts --collection <name> --reason \"...\"");
    process.exit(1);
  }

  auditLog("api-create", options.name, "success", undefined);
  // ... rest of function
}
```

---

## Phase 4: Update Commands (20 min)

### Task 4.1: Create `/bw-elevate` Command (Instructional)

**New file:** `~/.claude/commands/bw-elevate.md`

```markdown
---
description: Instruct user to elevate Vaultwarden access for RW operations
---

To perform write operations on Vaultwarden, you need to elevate your session.

**Run this command in YOUR terminal** (not here):

```bash
bun run ~/.claude/tools/vaultwarden/bw-elevate.ts \
  --collection <COLLECTION> \
  --reason "Your reason here"
```

**Available collections:**
- `bnx-infra` — BoroughNexus infrastructure
- `bnx-secrets` — BoroughNexus application secrets
- `briefhours-deploy` — BriefHours deployment

**Example:**
```bash
bun run ~/.claude/tools/vaultwarden/bw-elevate.ts \
  --collection briefhours-deploy \
  --reason "Deploying webapp v1.2.3"
```

Once complete, let me know and I can proceed with the write operation.
```

### Task 4.2: Update `/vault` Help

**File:** `~/.claude/commands/vault.md`

```markdown
---
description: Check vault API status and show available commands
---

## Vaultwarden Access Model

**Read Operations (Autonomous):**
- `/vault-get <name>` — Retrieve credential
- `/vault-search <query>` — Search credentials

Claude accesses RO collections automatically. No approval needed.

**Write Operations (Elevated):**
Requires you to run `bw-elevate` in your terminal first.
See `/bw-elevate` for instructions.

## Security

- Credentials stored in macOS Keychain (not files)
- RO/RW separation enforced by Vaultwarden collections
- All access logged to audit log
- No Telegram approval (structural security instead)
```

### Task 4.3: Mark `/vault-start` as Deprecated

**File:** `~/.claude/commands/vault-start.template.md`

Add at top:

```markdown
> **DEPRECATED:** Auto-start handles this. Use `/vault-get` or `/vault-search` directly.
```

---

## Phase 5: Testing & Validation (30 min)

### Test Sequence

1. **Setup Keychain (includes master password):**
   ```bash
   bun run ~/.claude/tools/vaultwarden/setup-keychain.ts
   ```

2. **Test RO Access:**
   ```bash
   bun run ~/.claude/tools/vaultwarden/bw-wrapper.ts api-search "test"
   # Should auto-start and return results
   ```

3. **Test RW Rejection Without Elevation:**
   ```bash
   bun run ~/.claude/tools/vaultwarden/bw-wrapper.ts api-create --name=test
   # Should fail with "requires elevated session" message
   ```

4. **Test Elevation Flow:**
   ```bash
   bun run ~/.claude/tools/vaultwarden/bw-elevate.ts \
     --collection briefhours-deploy \
     --reason "Testing elevation"
   # Should prompt for password, create session
   ```

5. **Test RW After Elevation:**
   ```bash
   bun run ~/.claude/tools/vaultwarden/bw-wrapper.ts api-create --name=test-item
   # Should succeed
   ```

6. **Verify Audit Log:**
   ```bash
   tail -20 ~/.claude/tools/vaultwarden/audit.log
   ```

### Validation Checklist

- [ ] Keychain stores all 4 fields (url, client_id, secret, password)
- [ ] `/vault-get` works autonomously
- [ ] `/vault-search` works autonomously
- [ ] `api-create` rejected without elevation
- [ ] `api-update` rejected without elevation
- [ ] `bw-elevate` prompts for password (not echoed)
- [ ] Elevated session persists for TTL
- [ ] Expired sessions are cleaned up
- [ ] Audit log captures all operations

---

## File Summary

| File | Action | Description |
|------|--------|-------------|
| `constants.ts` | Create | Shared constants (single source of truth) |
| `keychain.ts` | Create | Keychain helper functions |
| `setup-keychain.ts` | Create | One-time credential setup |
| `bw-elevate.ts` | Create | User-run elevation script |
| `bw-wrapper.ts` | Modify | Remove Telegram, add Keychain, check elevation |
| `bw-elevate.md` | Create | Instructional command for user |
| `vault.md` | Modify | Updated help text |
| `vault-start.template.md` | Modify | Add deprecation notice |

---

## Security Model Summary

| Aspect | Implementation |
|--------|----------------|
| RO/RW separation | Vaultwarden collection assignments (structural) |
| RO credentials | macOS Keychain (API key + master password) |
| RW access | User runs bw-elevate manually (password never in chat) |
| Session expiry | TTL files, checked on each operation |
| Audit trail | All operations logged with timestamps |
| Password handling | `stty -echo`, never stored in chat context |

---

## Rollback Plan

1. Restore from git: `git checkout HEAD~1 -- ~/.claude/tools/vaultwarden/`
2. Delete Keychain entry: `security delete-generic-password -s vaultwarden-claude -a api-credentials`
3. Restore `vault-secrets.json` from backup
