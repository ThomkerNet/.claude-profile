#!/usr/bin/env bun
/**
 * Check for pending Telegram instructions (UserPromptSubmit hook)
 * Outputs instructions as additionalContext so Claude acts on them
 * Reacts with 👍 and replies to "instruction queued" message
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

    // Output as additionalContext so Claude sees and acts on it
    const texts = instructions.map((i) => i.text);
    const context = `<user-prompt-submit-hook>
TELEGRAM INSTRUCTION FROM USER (act on this immediately):
${texts.join("\n\n")}
</user-prompt-submit-hook>`;

    console.log(JSON.stringify({
      hookSpecificOutput: {
        additionalContext: context
      }
    }));
  }
}

main();
