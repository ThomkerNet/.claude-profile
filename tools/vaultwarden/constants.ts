/**
 * Shared constants for Vaultwarden tools.
 * Single source of truth to avoid duplication.
 */

import { homedir } from "os";
import { join } from "path";
import { existsSync, mkdirSync } from "fs";

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

// Ensure TOOLS_DIR exists
if (!existsSync(TOOLS_DIR)) {
  mkdirSync(TOOLS_DIR, { recursive: true, mode: 0o700 });
}

// Server config - BNX vault for Claude autonomous access (claude@boroughnexus.com)
export const VAULTWARDEN_URL = process.env.BW_SERVER || "https://vault.boroughnexus.com";
export const API_PORT = 8087;
export const API_BASE = `http://localhost:${API_PORT}`;
export const DEFAULT_TTL_MINUTES = 30;

// Platform detection
export const IS_WINDOWS = process.platform === "win32";
export const IS_MACOS = process.platform === "darwin";
export const BW_CMD = IS_WINDOWS ? "bw.cmd" : "bw";

// Valid RW collections (must match Vaultwarden setup)
export const RW_COLLECTIONS = [
  "bnx-infra",
  "bnx-secrets",
  "briefhours-deploy",
];
