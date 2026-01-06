#!/usr/bin/env bun
/**
 * Vaultwarden/Bitwarden CLI Wrapper
 *
 * Provides programmatic access to Vaultwarden vault items.
 * Uses the official Bitwarden CLI configured for a self-hosted instance.
 *
 * Two modes of operation:
 * 1. Direct CLI mode (requires interactive unlock)
 * 2. REST API mode via `bw serve` (autonomous access for Claude)
 *
 * Usage:
 *   bun run bw-wrapper.ts login
 *   bun run bw-wrapper.ts unlock
 *   bun run bw-wrapper.ts get <name-or-id>
 *   bun run bw-wrapper.ts search <query>
 *   bun run bw-wrapper.ts list [folders|items|collections]
 *   bun run bw-wrapper.ts generate [--length=16] [--special]
 *   bun run bw-wrapper.ts status
 *   bun run bw-wrapper.ts lock
 *   bun run bw-wrapper.ts start                  # Start API server (background)
 *   bun run bw-wrapper.ts stop                   # Stop API server
 *   bun run bw-wrapper.ts api-search <query>     # Search via API (autonomous)
 *   bun run bw-wrapper.ts api-get <name>         # Get via API (autonomous)
 */

import { $ } from "bun";
import { existsSync, readFileSync, writeFileSync, unlinkSync, appendFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { getKeychainCredentials } from "./keychain";
import {
  SECRETS_FILE,
  ELEVATED_SESSION_FILE,
  ELEVATED_TTL_FILE,
} from "./constants";

// Configuration
const VAULTWARDEN_URL = process.env.BW_SERVER || "https://vaultwarden.thomker.net";
const SESSION_FILE = join(homedir(), ".claude", "tools", "vaultwarden", ".bw-session");
const PID_FILE = join(homedir(), ".claude", "tools", "vaultwarden", ".bw-serve.pid");
const TTL_FILE = join(homedir(), ".claude", "tools", "vaultwarden", ".bw-serve.ttl");
const AUDIT_LOG = join(homedir(), ".claude", "tools", "vaultwarden", "audit.log");
const CONFIG_FILE = join(homedir(), ".claude", "secrets.json");
const SECRETS_FILE = join(homedir(), ".claude", "tools", "vaultwarden", "vault-secrets.json");
const SECRETS_EXAMPLE = join(homedir(), ".claude", "tools", "vaultwarden", "vault-secrets.example.json");
const IS_WINDOWS = process.platform === "win32";
const BW_CMD = IS_WINDOWS ? "bw.cmd" : "bw";
const API_PORT = 8087;
const API_BASE = `http://localhost:${API_PORT}`;
const DEFAULT_TTL_MINUTES = 30; // Default session timeout


interface VaultItem {
  id: string;
  name: string;
  login?: {
    username?: string;
    password?: string;
    uris?: { uri: string }[];
    totp?: string;
  };
  notes?: string;
  fields?: { name: string; value: string }[];
}

interface VaultSecrets {
  client_id: string;
  client_secret: string;
  master_password: string;
}

// ============================================
// Secret Management (Keychain preferred, file fallback)
// ============================================

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
    console.warn("⚠️  Using file-based secrets (deprecated). Run setup-keychain.ts to migrate.");
    try {
      const secrets = JSON.parse(readFileSync(SECRETS_FILE, "utf-8")) as VaultSecrets;
      if (!secrets.client_id || !secrets.client_secret || !secrets.master_password) {
        console.error("❌ Vault secrets file incomplete.");
        console.error("   Required fields: client_id, client_secret, master_password");
        process.exit(1);
      }
      return secrets;
    } catch (error: any) {
      console.error("❌ Failed to parse vault secrets:", error.message);
      process.exit(1);
    }
  }

  console.error("❌ No vault credentials found.");
  console.error("   Run: bun run setup-keychain.ts");
  process.exit(1);
}

/**
 * Ensure vault is unlocked, using API key + master password from secrets file.
 * Returns session key.
 */
async function ensureUnlocked(): Promise<string> {
  // Check if we already have a valid session
  const existingSession = getSession();
  if (existingSession) {
    try {
      const statusOutput = await $`${BW_CMD} status`.env({
        ...process.env as Record<string, string>,
        BW_SESSION: existingSession,
        BW_SERVER: VAULTWARDEN_URL
      }).text();
      const status = JSON.parse(statusOutput);
      if (status.status === "unlocked") {
        return existingSession;
      }
    } catch {
      // Session invalid, continue to unlock
    }
  }

  // Load secrets from Keychain (or file fallback)
  const secrets = await loadVaultSecrets();

  // Check current status
  let vaultStatus: string;
  try {
    const statusOutput = await $`${BW_CMD} status`.env({
      ...process.env as Record<string, string>,
      BW_SERVER: VAULTWARDEN_URL
    }).text();
    const statusJson = JSON.parse(statusOutput);
    vaultStatus = statusJson.status;
  } catch (error: any) {
    console.error("❌ Failed to check vault status:", error.message);
    process.exit(1);
  }

  // Login with API key if unauthenticated
  if (vaultStatus === "unauthenticated") {
    console.log("Logging in with API key...");
    try {
      await $`${BW_CMD} login --apikey`.env({
        ...process.env as Record<string, string>,
        BW_SERVER: VAULTWARDEN_URL,
        BW_CLIENTID: secrets.client_id,
        BW_CLIENTSECRET: secrets.client_secret
      }).quiet();
      console.log("✓ Logged in");
    } catch (error: any) {
      console.error("❌ API key login failed:", error.message);
      process.exit(1);
    }
  }

  // Unlock with master password
  console.log("Unlocking vault...");
  try {
    const unlockResult = await $`${BW_CMD} unlock --passwordenv BW_PASSWORD --raw`.env({
      ...process.env as Record<string, string>,
      BW_SERVER: VAULTWARDEN_URL,
      BW_PASSWORD: secrets.master_password
    }).text();

    const session = unlockResult.trim();
    if (!session) {
      throw new Error("No session key returned");
    }

    saveSession(session);
    console.log("✓ Vault unlocked");
    return session;
  } catch (error: any) {
    console.error("❌ Failed to unlock vault:", error.message);
    process.exit(1);
  }
}

/**
 * Ensure the API server is running, auto-starting if needed.
 * This is the lazy auto-start function.
 */
async function ensureServerRunning(ttlMinutes: number = DEFAULT_TTL_MINUTES): Promise<void> {
  // Check if already running and healthy
  if (await isServerRunning()) {
    try {
      const response = await fetch(`${API_BASE}/status`, { signal: AbortSignal.timeout(2000) });
      const data = await response.json() as { data?: { template?: { status?: string } } };
      if (data.data?.template?.status === "unlocked") {
        // Server running and vault unlocked - we're good
        return;
      }
      // Server running but vault locked - stop it first
      console.log("Server running but vault locked. Restarting...");
      await stopServer();
    } catch {
      // Server not responding properly, stop and restart
      await stopServer();
    }
  }

  // Ensure vault is unlocked (uses secrets file)
  const session = await ensureUnlocked();

  // Start the server
  console.log("Starting API server...");

  const env: Record<string, string> = {
    ...process.env as Record<string, string>,
    BW_SESSION: session,
    BW_SERVER: VAULTWARDEN_URL,
  };

  const serverProc = Bun.spawn([BW_CMD, "serve", "--port", String(API_PORT)], {
    env,
    stdout: "ignore",
    stderr: "ignore",
    stdin: "ignore",
  });

  writeFileSync(PID_FILE, String(serverProc.pid), { mode: 0o600 });
  setSessionExpiry(ttlMinutes);

  // Poll for readiness
  const maxAttempts = 20; // 10 seconds
  let attempts = 0;
  while (attempts < maxAttempts) {
    await new Promise(r => setTimeout(r, 500));
    if (await isServerRunning()) {
      auditLog("server_auto_start", "", "success");
      console.log(`✓ Vault API server ready on port ${API_PORT}`);
      return;
    }
    attempts++;
  }

  console.error("❌ Server failed to start");
  await stopServer();
  process.exit(1);
}

// Get session key from file or environment
function getSession(): string | null {
  if (process.env.BW_SESSION) {
    return process.env.BW_SESSION;
  }
  if (existsSync(SESSION_FILE)) {
    return readFileSync(SESSION_FILE, "utf-8").trim();
  }
  return null;
}

function saveSession(session: string): void {
  writeFileSync(SESSION_FILE, session, { mode: 0o600 });
}

// Audit logging
function auditLog(action: string, query: string, result: string, itemCount?: number): void {
  const timestamp = new Date().toISOString();
  const entry = JSON.stringify({
    timestamp,
    action,
    query,
    result,
    itemCount,
  }) + "\n";

  try {
    appendFileSync(AUDIT_LOG, entry, { mode: 0o600 });
  } catch (e) {
    // Silently fail if we can't write audit log
  }
}

// ============================================
// Elevated Session Management (RW operations)
// ============================================

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

function requireElevation(operation: string): void {
  const elevated = getElevatedSession();
  if (!elevated) {
    console.error(`❌ RW operation "${operation}" requires elevated session.`);
    console.error("");
    console.error("Please run in your terminal:");
    console.error("  bun run ~/.claude/tools/vaultwarden/bw-elevate.ts \\");
    console.error('    --collection <name> --reason "Your reason"');
    console.error("");
    console.error("Available collections: bnx-infra, bnx-secrets, briefhours-deploy");
    process.exit(1);
  }
}

// Check if session has expired based on TTL
function isSessionExpired(): boolean {
  if (!existsSync(TTL_FILE)) return false;
  try {
    const expiryTime = parseInt(readFileSync(TTL_FILE, "utf-8").trim());
    return Date.now() > expiryTime;
  } catch {
    return false;
  }
}

function setSessionExpiry(ttlMinutes: number): void {
  const expiryTime = Date.now() + (ttlMinutes * 60 * 1000);
  writeFileSync(TTL_FILE, String(expiryTime), { mode: 0o600 });
}

// Get server URL from secrets.json
function getServerUrl(): string {
  if (existsSync(CONFIG_FILE)) {
    try {
      const secrets = JSON.parse(readFileSync(CONFIG_FILE, "utf-8"));
      return secrets.vaultwarden?.server || VAULTWARDEN_URL;
    } catch {
      return VAULTWARDEN_URL;
    }
  }
  return VAULTWARDEN_URL;
}

// Run bw command with session
async function bw(args: string[], options: { session?: boolean; json?: boolean } = {}): Promise<string> {
  const session = getSession();
  const env: Record<string, string> = {
    ...process.env as Record<string, string>,
    BW_SERVER: VAULTWARDEN_URL,
  };

  if (options.session !== false && session) {
    env.BW_SESSION = session;
  }

  const cmd = [BW_CMD, ...args];
  if (options.json !== false && !args.includes("--raw") && !["config", "login", "unlock", "lock", "serve", "status"].some(c => args[0] === c)) {
    cmd.push("--response");
  }

  try {
    const result = await $`${cmd}`.env(env).text();
    return result.trim();
  } catch (error: any) {
    throw new Error(error.stderr || error.message);
  }
}

// ============================================
// REST API Functions (for autonomous access)
// ============================================

async function isServerRunning(): Promise<boolean> {
  try {
    const response = await fetch(`${API_BASE}/status`, { signal: AbortSignal.timeout(1000) });
    return response.ok;
  } catch {
    return false;
  }
}

async function apiRequest(endpoint: string): Promise<any> {
  // Check TTL - if expired, server will be restarted by ensureServerRunning()
  if (isSessionExpired()) {
    auditLog("session_expired", endpoint, "restarting");
    console.log("Session expired, restarting server...");
    await stopServer();
    await ensureServerRunning();
  }

  const response = await fetch(`${API_BASE}${endpoint}`);
  const data = await response.json();

  // Check if vault is locked (session expired) - try to recover
  if (data.success === false && data.message?.includes("locked")) {
    auditLog("vault_locked", endpoint, "restarting");
    console.log("Vault locked, restarting server...");
    await stopServer();
    await ensureServerRunning();
    // Retry the request
    const retryResponse = await fetch(`${API_BASE}${endpoint}`);
    const retryData = await retryResponse.json();
    if (!retryResponse.ok && !retryData.success) {
      auditLog("api_error", endpoint, "error");
      throw new Error(`API error: ${retryResponse.status} - ${retryData.message || retryResponse.statusText}`);
    }
    return retryData;
  }

  if (!response.ok && !data.success) {
    auditLog("api_error", endpoint, "error");
    throw new Error(`API error: ${response.status} - ${data.message || response.statusText}`);
  }
  return data;
}


async function apiSearch(query: string): Promise<void> {
  // Auto-start server if needed (uses Keychain for auth)
  await ensureServerRunning();

  const data = await apiRequest(`/list/object/items?search=${encodeURIComponent(query)}`);

  // API returns { success, data: { object, data: [...items] } }
  const items = data.data?.data || data.data || [];
  if (data.success && items.length > 0) {
    auditLog("api-search", query, "success", items.length);
    console.log(`Found ${items.length} item(s):\n`);
    items.forEach((item: VaultItem) => {
      printItem(item);
      console.log("");
    });
  } else {
    auditLog("api-search", query, "not_found", 0);
    console.log(`No items found matching "${query}"`);
  }
}

async function apiGet(query: string): Promise<void> {
  // Auto-start server if needed (uses Keychain for auth)
  await ensureServerRunning();

  // First try exact match by name
  const data = await apiRequest(`/list/object/items?search=${encodeURIComponent(query)}`);

  // API returns { success, data: { object, data: [...items] } }
  const items = data.data?.data || data.data || [];
  if (data.success && items.length > 0) {
    // Try exact name match first
    const exact = items.find((i: VaultItem) => i.name.toLowerCase() === query.toLowerCase());
    if (exact) {
      auditLog("api-get", query, "success", 1);
      printItem(exact);
    } else if (items.length === 1) {
      auditLog("api-get", query, "success", 1);
      printItem(items[0]);
    } else {
      auditLog("api-get", query, "multiple_matches", items.length);
      console.log(`Found ${items.length} items matching "${query}":\n`);
      items.forEach((item: VaultItem) => {
        printItem(item);
        console.log("");
      });
    }
  } else {
    auditLog("api-get", query, "not_found", 0);
    console.log(`No items found matching "${query}"`);
  }
}

interface CreateItemOptions {
  name: string;
  username?: string;
  password?: string;
  url?: string;
  notes?: string;
  totp?: string;
}

async function apiCreate(options: CreateItemOptions): Promise<void> {
  // RW operation - require elevation
  requireElevation("api-create");

  // Auto-start server if needed (uses Keychain for auth)
  await ensureServerRunning();

  // Build the item payload
  const item = {
    type: 1, // Login type
    name: options.name,
    login: {
      username: options.username || null,
      password: options.password || null,
      uris: options.url ? [{ uri: options.url }] : [],
      totp: options.totp || null,
    },
    notes: options.notes || null,
  };

  try {
    const response = await fetch(`${API_BASE}/object/item`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(item),
    });

    const data = await response.json();

    if (data.success) {
      auditLog("api-create", options.name, "success");
      console.log(`✓ Created credential: ${options.name}`);
      console.log(`  ID: ${data.data?.id || "unknown"}`);
    } else {
      auditLog("api-create", options.name, "error: " + data.message);
      console.error(`❌ Failed to create: ${data.message}`);
    }
  } catch (error: any) {
    auditLog("api-create", options.name, "error: " + error.message);
    console.error(`❌ Error: ${error.message}`);
  }
}

async function apiUpdate(nameOrId: string, updates: Partial<CreateItemOptions>): Promise<void> {
  // RW operation - require elevation
  requireElevation("api-update");

  // Auto-start server if needed (uses Keychain for auth)
  await ensureServerRunning();

  // First, find the item
  const searchData = await apiRequest(`/list/object/items?search=${encodeURIComponent(nameOrId)}`);
  const items = searchData.data?.data || searchData.data || [];

  let targetItem: any = null;

  // Try exact ID match first
  targetItem = items.find((i: VaultItem) => i.id === nameOrId);

  // Then try exact name match
  if (!targetItem) {
    targetItem = items.find((i: VaultItem) => i.name.toLowerCase() === nameOrId.toLowerCase());
  }

  // If still no match and only one result, use it
  if (!targetItem && items.length === 1) {
    targetItem = items[0];
  }

  if (!targetItem) {
    if (items.length > 1) {
      auditLog("api-update", nameOrId, "error_multiple_matches");
      console.error(`❌ Multiple items match "${nameOrId}". Please use the exact ID:`);
      items.forEach((i: VaultItem) => console.log(`  - ${i.name} (${i.id})`));
    } else {
      auditLog("api-update", nameOrId, "not_found");
      console.error(`❌ No item found matching "${nameOrId}"`);
    }
    process.exit(1);
  }

  // Merge updates into existing item
  const updatedItem = {
    ...targetItem,
    name: updates.name || targetItem.name,
    notes: updates.notes !== undefined ? updates.notes : targetItem.notes,
    login: {
      ...targetItem.login,
      username: updates.username !== undefined ? updates.username : targetItem.login?.username,
      password: updates.password !== undefined ? updates.password : targetItem.login?.password,
      totp: updates.totp !== undefined ? updates.totp : targetItem.login?.totp,
      uris: updates.url ? [{ uri: updates.url }] : targetItem.login?.uris,
    },
  };

  try {
    const response = await fetch(`${API_BASE}/object/item/${targetItem.id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(updatedItem),
    });

    const data = await response.json();

    if (data.success) {
      auditLog("api-update", `${targetItem.name} (${targetItem.id})`, "success");
      console.log(`✓ Updated credential: ${targetItem.name}`);
    } else {
      auditLog("api-update", targetItem.id, "error: " + data.message);
      console.error(`❌ Failed to update: ${data.message}`);
    }
  } catch (error: any) {
    auditLog("api-update", targetItem.id, "error: " + error.message);
    console.error(`❌ Error: ${error.message}`);
  }
}

async function apiStatus(): Promise<void> {
  const running = await isServerRunning();
  if (running) {
    // Check TTL
    let ttlInfo = "";
    if (existsSync(TTL_FILE)) {
      const expiryTime = parseInt(readFileSync(TTL_FILE, "utf-8").trim());
      const remaining = Math.max(0, Math.floor((expiryTime - Date.now()) / 60000));
      if (remaining > 0) {
        ttlInfo = ` (expires in ${remaining} min)`;
      } else {
        ttlInfo = " (EXPIRED)";
      }
    }

    // Check if vault is actually unlocked
    try {
      const response = await fetch(`${API_BASE}/status`);
      const data = await response.json();
      if (data.success && data.data?.template?.status === "unlocked") {
        console.log("✓ Vault API server is running on port " + API_PORT + ttlInfo);
        console.log("✓ Vault is unlocked");
        console.log("  Claude can access credentials autonomously.");
      } else if (data.data?.template?.status === "locked") {
        console.log("✓ Vault API server is running on port " + API_PORT);
        console.log("✗ Vault is LOCKED (session expired)");
        console.log("  Please run: /vault-start");
      } else {
        console.log("✓ Vault API server is running on port " + API_PORT + ttlInfo);
        console.log("  Status: " + JSON.stringify(data));
      }
    } catch {
      console.log("✓ Vault API server is running on port " + API_PORT + ttlInfo);
    }
  } else {
    console.log("✗ Vault API server is not running");
    console.log("  Please run: /vault-start");
  }
}

async function startServer(ttlMinutes: number = DEFAULT_TTL_MINUTES): Promise<void> {
  // Check if already running
  if (await isServerRunning()) {
    console.log("✓ Vault API server already running on port " + API_PORT);
    return;
  }

  const session = getSession();
  if (!session) {
    console.error("No session found. Please unlock the vault first:");
    console.error("  bw unlock");
    process.exit(1);
  }

  console.log("Starting Bitwarden API server...");

  const env: Record<string, string> = {
    ...process.env as Record<string, string>,
    BW_SESSION: session,
    BW_SERVER: VAULTWARDEN_URL,
  };

  // Start bw serve in background
  const proc = Bun.spawn([BW_CMD, "serve", "--port", String(API_PORT)], {
    env,
    stdout: "ignore",
    stderr: "ignore",
    stdin: "ignore",
  });

  // Save PID for later
  writeFileSync(PID_FILE, String(proc.pid), { mode: 0o600 });

  // Set session expiry TTL
  setSessionExpiry(ttlMinutes);

  // Wait for server to start
  let attempts = 0;
  while (attempts < 10) {
    await new Promise(r => setTimeout(r, 500));
    if (await isServerRunning()) {
      auditLog("server_start", "", "success");
      console.log(`✓ Vault API server started on http://localhost:${API_PORT}`);
      console.log(`✓ Session expires in ${ttlMinutes} minutes`);
      console.log("  Claude can now access credentials autonomously.");
      console.log("  Run '/vault-stop' to shut down the server.");
      return;
    }
    attempts++;
  }

  console.error("Failed to start server within timeout");
  process.exit(1);
}

async function stopServer(): Promise<void> {
  const { unlinkSync } = await import("fs");

  if (!existsSync(PID_FILE)) {
    console.log("No server PID file found.");
    // Still clean up TTL file if it exists
    try { unlinkSync(TTL_FILE); } catch {}
    return;
  }

  const pid = parseInt(readFileSync(PID_FILE, "utf-8").trim());

  try {
    if (IS_WINDOWS) {
      Bun.spawn(["taskkill", "/F", "/PID", String(pid)], { stdout: "ignore", stderr: "ignore" });
    } else {
      process.kill(pid, "SIGTERM");
    }
    auditLog("server_stop", "", "success");
    console.log("✓ Vault API server stopped");
  } catch (e) {
    console.log("Server may have already stopped");
  }

  // Clean up PID and TTL files
  try { unlinkSync(PID_FILE); } catch {}
  try { unlinkSync(TTL_FILE); } catch {}
}

/**
 * Unified vault-start command that handles:
 * 1. Check if server already running and unlocked
 * 2. Check vault status and unlock if needed
 * 3. Start the API server
 * 4. Wait for server to be ready
 */
async function vaultStart(ttlMinutes: number = DEFAULT_TTL_MINUTES): Promise<void> {
  // Step 1: Check if server already running and working
  if (await isServerRunning()) {
    try {
      const response = await fetch(`${API_BASE}/status`, { signal: AbortSignal.timeout(2000) });
      const data = await response.json() as { data?: { template?: { status?: string } } };
      if (data.data?.template?.status === "unlocked") {
        console.log("✓ Vault API server already running and unlocked");
        console.log(`  Server: http://localhost:${API_PORT}`);
        return;
      }
      // Server running but vault locked - stop it first
      console.log("Server running but vault locked. Restarting...");
      await stopServer();
    } catch {
      // Server not responding properly, stop and restart
      console.log("Server not responding properly. Restarting...");
      await stopServer();
    }
  }

  // Step 2: Check vault status
  let vaultStatus: string;
  try {
    const statusOutput = await $`${BW_CMD} status`.env({
      ...process.env as Record<string, string>,
      BW_SERVER: VAULTWARDEN_URL
    }).text();
    const statusJson = JSON.parse(statusOutput);
    vaultStatus = statusJson.status;
  } catch (error: any) {
    console.error("❌ Failed to check vault status:", error.message);
    process.exit(1);
  }

  if (vaultStatus === "unauthenticated") {
    console.error("❌ Not logged in to Bitwarden.");
    console.error("   Please run: bw login");
    process.exit(1);
  }

  // Step 3: Unlock if needed
  if (vaultStatus === "locked") {
    console.log("Vault is locked. Unlocking...");
    console.log("(Enter your master password below)\n");

    const proc = Bun.spawn([BW_CMD, "unlock", "--raw"], {
      env: {
        ...process.env as Record<string, string>,
        BW_SERVER: VAULTWARDEN_URL
      },
      stdin: "inherit",
      stdout: "pipe",
      stderr: "inherit",
    });

    const output = await new Response(proc.stdout).text();
    await proc.exited;

    if (proc.exitCode !== 0 || !output.trim()) {
      console.error("\n❌ Failed to unlock vault");
      process.exit(1);
    }

    const session = output.trim();
    saveSession(session);
    console.log("\n✓ Vault unlocked");
  } else {
    console.log("✓ Vault already unlocked");
  }

  // Step 4: Start the API server
  const session = getSession();
  if (!session) {
    console.error("❌ No session found after unlock");
    process.exit(1);
  }

  console.log("Starting API server...");

  const env: Record<string, string> = {
    ...process.env as Record<string, string>,
    BW_SESSION: session,
    BW_SERVER: VAULTWARDEN_URL,
  };

  const serverProc = Bun.spawn([BW_CMD, "serve", "--port", String(API_PORT)], {
    env,
    stdout: "ignore",
    stderr: "ignore",
    stdin: "ignore",
  });

  writeFileSync(PID_FILE, String(serverProc.pid), { mode: 0o600 });
  setSessionExpiry(ttlMinutes);

  // Step 5: Poll for readiness
  const maxAttempts = 20; // 10 seconds
  let attempts = 0;
  while (attempts < maxAttempts) {
    await new Promise(r => setTimeout(r, 500));
    if (await isServerRunning()) {
      auditLog("vault_start", "", "success");
      console.log(`\n✓ Vault API server ready on http://localhost:${API_PORT}`);
      console.log(`✓ Session expires in ${ttlMinutes} minutes`);
      console.log("  Claude can now access credentials autonomously.");
      return;
    }
    attempts++;
  }

  // Timeout - cleanup
  console.error("\n❌ Server failed to start within 10 seconds");
  await stopServer();
  process.exit(1);
}

// ============================================
// CLI Commands (interactive mode)
// ============================================

async function configure(): Promise<void> {
  console.log(`Configuring Bitwarden CLI for ${VAULTWARDEN_URL}...`);
  const proc = Bun.spawn([BW_CMD, "config", "server", VAULTWARDEN_URL], {
    env: process.env as Record<string, string>,
    stdout: "inherit",
    stderr: "inherit",
  });
  await proc.exited;
  console.log("✓ Server configured");
}

async function login(): Promise<void> {
  // Check if already logged in
  try {
    const status = await bw(["status"], { session: false });
    const parsed = JSON.parse(status);
    if (parsed.status !== "unauthenticated") {
      console.log("Already logged in. Use 'unlock' to get a session.");
      return;
    }
  } catch {}

  // Configure server first
  await configure();

  // Interactive login
  console.log("Starting interactive login...");
  console.log("(You'll be prompted for email and master password)\n");

  const env: Record<string, string> = {
    ...process.env as Record<string, string>,
    BW_SERVER: getServerUrl(),
  };

  // Run bw login interactively (inherits stdin/stdout)
  const proc = Bun.spawn([BW_CMD, "login"], {
    env,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });

  await proc.exited;

  if (proc.exitCode === 0) {
    console.log("\n✓ Logged in successfully");
    console.log("Now run: bun run bw-wrapper.ts unlock");
  }
}

async function unlock(): Promise<void> {
  // Check if already unlocked with valid session
  const existingSession = getSession();
  if (existingSession) {
    try {
      const status = await bw(["status"]);
      const parsed = JSON.parse(status);
      if (parsed.status === "unlocked") {
        console.log("Vault is already unlocked.");
        return;
      }
    } catch {}
  }

  console.log("Unlocking vault...");
  console.log("(You'll be prompted for your master password)\n");

  const env: Record<string, string> = {
    ...process.env as Record<string, string>,
    BW_SERVER: getServerUrl(),
  };

  // Run bw unlock and capture session key
  const proc = Bun.spawn([BW_CMD, "unlock", "--raw"], {
    env,
    stdin: "inherit",
    stdout: "pipe",
    stderr: "inherit",
  });

  const output = await new Response(proc.stdout).text();
  await proc.exited;

  if (proc.exitCode === 0 && output.trim()) {
    const session = output.trim();
    saveSession(session);
    console.log("\n✓ Vault unlocked. Session saved to:");
    console.log(`  ${SESSION_FILE}`);
  } else {
    console.error("Failed to unlock vault");
  }
}

async function status(): Promise<void> {
  const result = await bw(["status"], { session: false });
  try {
    const parsed = JSON.parse(result);
    console.log(`Status: ${parsed.status}`);
    console.log(`Server: ${parsed.serverUrl || VAULTWARDEN_URL}`);
    if (parsed.userEmail) console.log(`User: ${parsed.userEmail}`);
    if (parsed.lastSync) console.log(`Last sync: ${parsed.lastSync}`);

    const session = getSession();
    console.log(`Session: ${session ? "Available" : "Not set"}`);
  } catch {
    console.log(result);
  }
}

async function get(query: string): Promise<void> {
  // Try to get by name first, then by ID
  try {
    const result = await bw(["get", "item", query]);
    const response = JSON.parse(result);

    if (response.success === false) {
      // Try searching
      const searchResult = await bw(["list", "items", "--search", query]);
      const searchResponse = JSON.parse(searchResult);

      if (searchResponse.success && searchResponse.data?.data?.length > 0) {
        const items = searchResponse.data.data;
        if (items.length === 1) {
          printItem(items[0]);
        } else {
          console.log(`Found ${items.length} items matching "${query}":`);
          items.forEach((item: VaultItem) => {
            console.log(`  - ${item.name} (${item.id})`);
          });
        }
      } else {
        console.log(`No items found matching "${query}"`);
      }
      return;
    }

    printItem(response.data);
  } catch (error: any) {
    console.error("Error:", error.message);
  }
}

function printItem(item: VaultItem, redactSecrets: boolean = true): void {
  console.log(`\n=== ${item.name} ===`);
  if (item.login) {
    if (item.login.username) console.log(`Username: ${item.login.username}`);
    if (item.login.password) {
      console.log(`Password: ${redactSecrets ? "********" : item.login.password}`);
    }
    if (item.login.uris?.length) {
      console.log(`URL: ${item.login.uris[0].uri}`);
    }
    if (item.login.totp) {
      console.log(`TOTP: ${redactSecrets ? "[REDACTED]" : item.login.totp}`);
    }
  }
  if (item.notes) console.log(`Notes: ${item.notes}`);
  if (item.fields?.length) {
    console.log("Custom fields:");
    item.fields.forEach(f => {
      // Redact fields that look like secrets
      const isSecret = /password|secret|key|token|api/i.test(f.name);
      console.log(`  ${f.name}: ${(redactSecrets && isSecret) ? "********" : f.value}`);
    });
  }
  console.log(`ID: ${item.id}`);
}

async function search(query: string): Promise<void> {
  const result = await bw(["list", "items", "--search", query]);
  const response = JSON.parse(result);

  if (response.success && response.data?.data?.length > 0) {
    const items = response.data.data;
    console.log(`Found ${items.length} items:\n`);
    items.forEach((item: VaultItem) => {
      console.log(`${item.name}`);
      if (item.login?.username) console.log(`  User: ${item.login.username}`);
      if (item.login?.uris?.length) console.log(`  URL: ${item.login.uris[0].uri}`);
      console.log(`  ID: ${item.id}\n`);
    });
  } else {
    console.log(`No items found matching "${query}"`);
  }
}

async function list(type: string = "items"): Promise<void> {
  const result = await bw(["list", type]);
  const response = JSON.parse(result);

  if (response.success && response.data?.data) {
    const items = response.data.data;
    console.log(`${items.length} ${type}:\n`);
    items.forEach((item: any) => {
      console.log(`- ${item.name} (${item.id})`);
    });
  } else {
    console.log(result);
  }
}

async function generate(options: { length?: number; special?: boolean } = {}): Promise<void> {
  const args = ["generate", "-l", String(options.length || 16)];
  if (options.special) args.push("-s");
  args.push("-u", "-n"); // uppercase, numbers

  const proc = Bun.spawn([BW_CMD, ...args], {
    env: process.env as Record<string, string>,
    stdout: "pipe",
  });
  const result = await new Response(proc.stdout).text();
  console.log(result.trim());
}

async function lock(): Promise<void> {
  await bw(["lock"], { session: false });
  // Remove session file
  if (existsSync(SESSION_FILE)) {
    const { unlinkSync } = await import("fs");
    unlinkSync(SESSION_FILE);
  }
  console.log("✓ Vault locked");
}

async function serve(port: number = 8087): Promise<void> {
  const session = getSession();
  if (!session) {
    console.error("No session. Run 'unlock' first.");
    process.exit(1);
  }

  console.log(`Starting Bitwarden API server on http://localhost:${port}`);
  console.log("Press Ctrl+C to stop.\n");

  const env: Record<string, string> = {
    ...process.env as Record<string, string>,
    BW_SESSION: session,
    BW_SERVER: VAULTWARDEN_URL,
  };

  const proc = Bun.spawn([BW_CMD, "serve", "--port", String(port)], {
    env,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  await proc.exited;
}

async function sync(): Promise<void> {
  await bw(["sync"]);
  console.log("✓ Vault synced");
}

// Main
const [command, ...args] = process.argv.slice(2);

switch (command) {
  case "config":
  case "configure":
    await configure();
    break;

  case "login":
    await login();
    break;

  case "unlock":
    await unlock();
    break;

  case "status":
    await status();
    break;

  case "get":
    if (!args[0]) {
      console.error("Usage: bw-wrapper.ts get <name-or-id>");
      process.exit(1);
    }
    await get(args.join(" "));
    break;

  case "search":
    if (!args[0]) {
      console.error("Usage: bw-wrapper.ts search <query>");
      process.exit(1);
    }
    await search(args.join(" "));
    break;

  case "list":
    await list(args[0] || "items");
    break;

  case "generate":
    const genOpts: { length?: number; special?: boolean } = {};
    args.forEach(arg => {
      if (arg.startsWith("--length=")) genOpts.length = parseInt(arg.split("=")[1]);
      if (arg === "--special" || arg === "-s") genOpts.special = true;
    });
    await generate(genOpts);
    break;

  case "lock":
    await lock();
    break;

  case "serve":
    let port = 8087;
    args.forEach(arg => {
      if (arg.startsWith("--port=")) port = parseInt(arg.split("=")[1]);
    });
    await serve(port);
    break;

  case "sync":
    await sync();
    break;

  // API server management
  case "vault-start":
    let vaultTtl = DEFAULT_TTL_MINUTES;
    args.forEach(arg => {
      if (arg.startsWith("--ttl=")) vaultTtl = parseInt(arg.split("=")[1]);
    });
    await vaultStart(vaultTtl);
    break;

  case "start":
    let ttl = DEFAULT_TTL_MINUTES;
    args.forEach(arg => {
      if (arg.startsWith("--ttl=")) ttl = parseInt(arg.split("=")[1]);
    });
    await startServer(ttl);
    break;

  case "stop":
    await stopServer();
    break;

  case "api-status":
    await apiStatus();
    break;

  // Autonomous API access (for Claude)
  case "api-search":
    if (!args[0]) {
      console.error("Usage: bw-wrapper.ts api-search <query>");
      process.exit(1);
    }
    await apiSearch(args.join(" "));
    break;

  case "api-get":
    if (!args[0]) {
      console.error("Usage: bw-wrapper.ts api-get <name>");
      process.exit(1);
    }
    await apiGet(args.join(" "));
    break;

  case "api-create":
    // Parse args: --name=X --username=X --password=X --url=X --notes=X
    const createOpts: CreateItemOptions = { name: "" };
    args.forEach(arg => {
      if (arg.startsWith("--name=")) createOpts.name = arg.slice(7);
      else if (arg.startsWith("--username=")) createOpts.username = arg.slice(11);
      else if (arg.startsWith("--password=")) createOpts.password = arg.slice(11);
      else if (arg.startsWith("--url=")) createOpts.url = arg.slice(6);
      else if (arg.startsWith("--notes=")) createOpts.notes = arg.slice(8);
      else if (arg.startsWith("--totp=")) createOpts.totp = arg.slice(7);
    });
    if (!createOpts.name) {
      console.error("Usage: bw-wrapper.ts api-create --name=NAME [--username=X] [--password=X] [--url=X] [--notes=X]");
      process.exit(1);
    }
    await apiCreate(createOpts);
    break;

  case "api-update":
    // First arg is name/id, rest are updates
    if (!args[0]) {
      console.error("Usage: bw-wrapper.ts api-update <name-or-id> [--password=X] [--username=X] [--url=X] [--notes=X]");
      process.exit(1);
    }
    const updateTarget = args[0];
    const updateOpts: Partial<CreateItemOptions> = {};
    args.slice(1).forEach(arg => {
      if (arg.startsWith("--name=")) updateOpts.name = arg.slice(7);
      else if (arg.startsWith("--username=")) updateOpts.username = arg.slice(11);
      else if (arg.startsWith("--password=")) updateOpts.password = arg.slice(11);
      else if (arg.startsWith("--url=")) updateOpts.url = arg.slice(6);
      else if (arg.startsWith("--notes=")) updateOpts.notes = arg.slice(8);
      else if (arg.startsWith("--totp=")) updateOpts.totp = arg.slice(7);
    });
    await apiUpdate(updateTarget, updateOpts);
    break;

  default:
    console.log(`
Vaultwarden CLI Wrapper

Usage:
  bun run bw-wrapper.ts <command> [options]

API Commands (Claude uses these - auto-start):
  api-get <name>      Get credential by name (RO - autonomous)
  api-search <query>  Search credentials (RO - autonomous)
  api-create          Create new credential (RW - requires elevation)
                      --name=NAME --username=X --password=X --url=X --notes=X
  api-update <name>   Update existing credential (RW - requires elevation)
                      --password=X --username=X --url=X --notes=X

Server Management:
  api-status          Check if API server is running
  stop                Stop API server

One-Time Setup (user runs once):
  bun run setup-keychain.ts
  - Stores credentials in macOS Keychain (not files)
  - Requires: server URL, client_id, client_secret, master_password

Security:
  - RO access: Autonomous via Keychain credentials
  - RW access: Requires user to run bw-elevate first
  - Session auto-expires after TTL (default ${DEFAULT_TTL_MINUTES} min)
  - All access logged to: ${AUDIT_LOG}
  - Passwords always redacted in output

Legacy Interactive Commands (manual use):
  config              Configure CLI for Vaultwarden server
  login               Login to Vaultwarden (interactive)
  unlock              Unlock vault interactively
  vault-start [--ttl] Manual unlock + start server (deprecated)
  status              Show current status
  lock                Lock vault and clear session
  get <name>          Get item (requires unlock)
  search <query>      Search items (requires unlock)
  list [type]         List items, folders, or collections
  generate [opts]     Generate a password (--length=N, --special)
  sync                Sync vault with server
  serve [--port=N]    Start local REST API server (foreground)

Claude Autonomous Workflow:
  1. User runs setup-keychain.ts (one-time)
  2. Claude uses api-get/api-search autonomously (RO)
  3. For RW: User runs bw-elevate.ts in terminal
  4. Claude uses api-create/api-update (with elevated session)

Environment:
  BW_SERVER    Vaultwarden URL (default: ${VAULTWARDEN_URL})
`);
}
