/**
 * macOS Keychain helpers for credential storage.
 * Note: This only works on macOS. On other platforms, falls back to file-based storage.
 */

import { KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT, IS_MACOS } from "./constants";

export interface KeychainCredentials {
  server_url: string;
  client_id: string;
  client_secret: string;
  master_password: string;  // Required for vault decryption
}

export async function getKeychainCredentials(): Promise<KeychainCredentials | null> {
  // Only works on macOS
  if (!IS_MACOS) {
    return null;
  }

  try {
    // Spawn directly without shell to avoid /bin/sh dependency
    const proc = Bun.spawn(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-w"], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const output = await new Response(proc.stdout).text();
    await proc.exited;

    if (proc.exitCode !== 0) {
      return null;
    }

    const parsed = JSON.parse(output.trim());

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
  if (!IS_MACOS) {
    throw new Error("Keychain storage only works on macOS");
  }

  const json = JSON.stringify(creds);
  // -U flag updates if exists, creates if not
  const proc = Bun.spawn(["security", "add-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-w", json, "-U"], {
    stdout: "pipe",
    stderr: "pipe",
  });
  await proc.exited;

  if (proc.exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(`Failed to store in Keychain: ${stderr}`);
  }
}

export async function deleteKeychainCredentials(): Promise<void> {
  if (!IS_MACOS) {
    return;
  }

  try {
    const proc = Bun.spawn(["security", "delete-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT], {
      stdout: "pipe",
      stderr: "pipe",
    });
    await proc.exited;
  } catch {
    // Ignore if not found
  }
}
