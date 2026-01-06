#!/usr/bin/env bun
/**
 * Telegram Notification Hook (Stop events)
 * Sends notifications when Claude needs input or completes tasks
 * Only sends if user is idle (Windows only)
 */

import { getConfig, getDefaultSession } from "./src/db";
import { sendMessage } from "./src/telegram";

// Windows idle detection via PowerShell
async function getIdleSeconds(): Promise<number> {
  try {
    const proc = Bun.spawn(["powershell", "-Command", `
      Add-Type @"
using System;
using System.Runtime.InteropServices;
public class IdleTime {
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    public static int Get() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref lii);
        return (Environment.TickCount - (int)lii.dwTime) / 1000;
    }
}
"@
[IdleTime]::Get()
    `]);
    const output = await new Response(proc.stdout).text();
    return parseInt(output.trim()) || 0;
  } catch {
    return 0; // Assume not idle if check fails
  }
}

async function main() {
  // Read hook input from stdin
  const input = await Bun.stdin.text();

  if (!input) {
    process.exit(0);
  }

  // Check idle threshold
  const idleThreshold = parseInt(getConfig("idle_threshold_seconds") || "180");
  const idleSeconds = await getIdleSeconds();

  if (idleSeconds < idleThreshold) {
    // User is active, skip notification
    process.exit(0);
  }

  try {
    const hookData = JSON.parse(input);
    const hookType = hookData.hook_type;
    const sessionId = getDefaultSession() || hookData.session_id?.slice(0, 8);

    let message = "";

    if (hookType === "Stop") {
      const stopReason = hookData.stop_hook_data?.stop_reason;

      switch (stopReason) {
        case "user_input_needed":
          message = `🔔 *Claude needs your input*\n\nSession: \`${sessionId}\`\n\nClaude is waiting for your decision or response.`;
          break;
        case "end_turn":
          message = `✅ *Claude completed a task*\n\nSession: \`${sessionId}\`\n\nClaude finished processing and is ready for next instructions.`;
          break;
        case "interrupt":
          message = `⏸️ *Claude was interrupted*\n\nSession: \`${sessionId}\``;
          break;
        default:
          message = `ℹ️ *Claude stopped*\n\nReason: ${stopReason}\nSession: \`${sessionId}\``;
      }
    } else {
      message = `ℹ️ *Claude Code Event*\n\nHook: ${hookType}\nSession: \`${sessionId}\``;
    }

    if (message) {
      await sendMessage(message);
    }
  } catch (error) {
    console.error("Hook error:", error);
  }
}

main();
