#!/usr/bin/env bun
/**
 * Stop hook - checks for Telegram instructions before allowing Claude to stop
 * If instructions exist, blocks the stop and injects them as context
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
  const ppid = process.ppid;
  const sessionByPid = ppid ? getSessionByPid(ppid) : null;
  const sessionId = process.argv[2] || sessionByPid?.id || getDefaultSession();

  if (!sessionId) {
    // No session, allow stop
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

    // Block the stop and inject instructions
    const texts = instructions.map((i) => i.text);
    console.log(JSON.stringify({
      decision: "block",
      reason: `Telegram instruction received - act on this:\n\n${texts.join("\n\n")}`
    }));
    process.exit(0);
  }

  // No instructions, allow stop (notify.ts will handle the notification)
  process.exit(0);
}

main();
