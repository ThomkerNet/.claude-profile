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

import * as readline from "readline";
import { KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT, VAULTWARDEN_URL } from "./constants";
import { setKeychainCredentials, getKeychainCredentials, type KeychainCredentials } from "./keychain";

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

async function disableEcho(): Promise<void> {
  if (process.platform !== "darwin" && process.platform !== "linux") return;
  try {
    const proc = Bun.spawn(["stty", "-echo"], { stdin: "inherit" });
    await proc.exited;
  } catch {}
}

async function enableEcho(): Promise<void> {
  if (process.platform !== "darwin" && process.platform !== "linux") return;
  try {
    const proc = Bun.spawn(["stty", "echo"], { stdin: "inherit" });
    await proc.exited;
  } catch {}
}

async function promptHidden(question: string): Promise<string> {
  process.stdout.write(question);

  await disableEcho();

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false,
  });

  return new Promise((resolve) => {
    rl.once("line", async (answer) => {
      rl.close();
      await enableEcho();
      console.log(); // Newline after hidden input
      resolve(answer.trim());
    });

    // Ensure echo is re-enabled on close/error
    rl.once("close", enableEcho);
  });
}

async function main() {
  console.log("=== BNX Vault Keychain Setup (Claude Service Account) ===\n");
  console.log("This stores claude@boroughnexus.com credentials in macOS Keychain.");
  console.log("Enables autonomous RO access to BNX vault collections.\n");
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

  // Pre-populated for claude@boroughnexus.com service account
  const DEFAULT_CLIENT_ID = "user.9cbf8bb7-f0ba-4850-8f19-8cb1671f3f56";

  const serverUrl = await prompt(`Vaultwarden URL [${VAULTWARDEN_URL}]: `);
  const clientIdInput = await prompt(`Client ID [${DEFAULT_CLIENT_ID}]: `);
  const clientId = clientIdInput || DEFAULT_CLIENT_ID;
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
  console.log("For RW operations, run bw-elevate.ts manually when needed.\n");
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
