#!/usr/bin/env bun
/**
 * PostToolUse hook - checks for Telegram instructions after each tool execution
 * This enables "background polling" - Claude can receive instructions while working
 * without waiting for user input or stop events
 */

import {
  getDefaultSession,
  getSessionByPid,
  getPendingInstructions,
  acknowledgeAllInstructions,
} from "./src/db";
import { reactToMessage, replyToMessage } from "./src/telegram";

async function main() {
  // Try to find session for this specific Claude process by PID
  // Falls back to default session if not found
  const ppid = process.ppid;
  const sessionByPid = ppid ? getSessionByPid(ppid) : null;
  const sessionId = process.argv[2] || sessionByPid?.id || getDefaultSession();

  if (!sessionId) {
    process.exit(0);
  }

  const instructions = getPendingInstructions(sessionId) as {
    id: string;
    text: string;
    message_id: number | null;
    queued_message_id: number | null;
  }[];

  if (instructions.length > 0) {
    acknowledgeAllInstructions(sessionId);

    // React with 👍 and reply "✅ Processed" to original message
    const promises: Promise<any>[] = [];
    for (const instruction of instructions) {
      if (instruction.message_id) {
        promises.push(reactToMessage(instruction.message_id));
        promises.push(replyToMessage(instruction.message_id, "✅ Processed"));
      }
    }
    await Promise.all(promises);

    // Output with decision: "block" to force Claude to process
    const texts = instructions.map((i) => i.text);

    console.log(JSON.stringify({
      decision: "block",
      reason: `TELEGRAM INSTRUCTION FROM USER - act on this:\n\n${texts.join("\n\n")}`
    }));
  }
}

main();
