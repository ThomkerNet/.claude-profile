/**
 * Simplified CLI for Telegram integration.
 * Only 3 commands: config, listen, status
 */

import { setConfig, getConfig } from "./db";
import { startListener } from "./listener";

const args = process.argv.slice(2);
const command = args[0];

async function main() {
  switch (command) {
    case "config": {
      const [, botToken, chatId] = args;
      if (!botToken || !chatId) {
        console.error("Usage: bun run index.ts config <bot_token> <chat_id>");
        process.exit(1);
      }
      setConfig("bot_token", botToken);
      setConfig("chat_id", chatId);
      console.log("✅ Configuration saved");
      break;
    }

    case "listen": {
      await startListener();
      break;
    }

    case "status": {
      const botToken = getConfig("bot_token");
      const chatId = getConfig("chat_id");
      console.log(`Bot Token: ${botToken ? "configured" : "not set"}`);
      console.log(`Chat ID: ${chatId ? "configured" : "not set"}`);
      break;
    }

    default:
      console.log(`Claude Telegram Bridge (Simplified)

Usage:
  bun run index.ts config <bot_token> <chat_id>  Configure bot credentials
  bun run index.ts listen                        Start the approval listener
  bun run index.ts status                        Show configuration status

This is a simplified version that only handles approval requests.
No sessions, instructions, or questions - just approvals with inline buttons.
`);
  }
}

main().catch(console.error);
