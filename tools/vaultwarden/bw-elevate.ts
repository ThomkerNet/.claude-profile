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
      console.log();
      resolve(answer.trim());
    });

    // Ensure echo is re-enabled on close/error
    rl.once("close", enableEcho);
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
    const proc = Bun.spawn(["whoami"], { stdout: "pipe" });
    const output = await new Response(proc.stdout).text();
    await proc.exited;
    return output.trim() || "unknown";
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
    // Spawn bw unlock directly without shell to avoid /bin/sh dependency
    const proc = Bun.spawn([BW_CMD, "unlock", "--passwordenv", "BW_PASSWORD", "--raw"], {
      env: {
        ...process.env as Record<string, string>,
        BW_SERVER: VAULTWARDEN_URL,
        BW_PASSWORD: password,
      },
      stdout: "pipe",
      stderr: "pipe",
    });

    const unlockResult = await new Response(proc.stdout).text();
    await proc.exited;

    if (proc.exitCode !== 0) {
      const stderr = await new Response(proc.stderr).text();
      throw new Error(stderr || "Unlock failed");
    }

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
