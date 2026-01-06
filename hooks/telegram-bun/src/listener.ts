/**
 * Simplified Telegram Listener
 *
 * Only handles approval button callbacks. No sessions, instructions, or questions.
 */

import { existsSync, readFileSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import {
  getConfig,
  setConfig,
  respondToApproval,
  getApproval,
  cleanupOldApprovals,
} from "./db";

const CONFIG_FILE = join(homedir(), ".claude", "hooks", "telegram-config.json");

interface TelegramConfig {
  bot_token: string;
  chat_id: string;
}

function getTelegramConfig(): TelegramConfig | null {
  if (existsSync(CONFIG_FILE)) {
    try {
      return JSON.parse(readFileSync(CONFIG_FILE, "utf-8"));
    } catch {
      // Fall through
    }
  }

  const botToken = getConfig("bot_token");
  const chatId = getConfig("chat_id");
  if (botToken && chatId) {
    return { bot_token: botToken, chat_id: chatId };
  }

  return null;
}

async function sendMessage(config: TelegramConfig, text: string): Promise<void> {
  try {
    await fetch(`https://api.telegram.org/bot${config.bot_token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: config.chat_id,
        text,
        parse_mode: "Markdown"
      })
    });
  } catch (error) {
    console.error("Failed to send message:", error);
  }
}

async function getUpdates(config: TelegramConfig, offset: number): Promise<any[]> {
  try {
    const response = await fetch(
      `https://api.telegram.org/bot${config.bot_token}/getUpdates?offset=${offset}&timeout=30`,
      { signal: AbortSignal.timeout(35000) }
    );
    const data = await response.json() as { ok: boolean; result: any[] };
    return data.ok ? data.result : [];
  } catch (error: any) {
    if (error.name !== "TimeoutError") {
      console.error("Polling error:", error.message);
    }
    return [];
  }
}

async function answerCallbackQuery(config: TelegramConfig, queryId: string, text: string): Promise<void> {
  try {
    await fetch(`https://api.telegram.org/bot${config.bot_token}/answerCallbackQuery`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ callback_query_id: queryId, text })
    });
  } catch {
    // Best effort
  }
}

async function editMessageRemoveKeyboard(
  config: TelegramConfig,
  chatId: number,
  messageId: number,
  text: string
): Promise<void> {
  try {
    await fetch(`https://api.telegram.org/bot${config.bot_token}/editMessageText`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        message_id: messageId,
        text,
        parse_mode: "Markdown"
      })
    });
  } catch {
    // Best effort
  }
}

async function handleCallbackQuery(
  config: TelegramConfig,
  queryId: string,
  data: string,
  chatId: number,
  messageId: number
): Promise<void> {
  // Format: approval:approvalId:value
  if (!data.startsWith("approval:")) {
    await answerCallbackQuery(config, queryId, "Unknown action");
    return;
  }

  const parts = data.split(":");
  const approvalId = parts[1];
  const selectedValue = parts.slice(2).join(":");

  const success = respondToApproval(approvalId, selectedValue);

  if (success) {
    const approval = getApproval(approvalId);
    const emoji = selectedValue === "allow" ? "✅" : "❌";
    const action = selectedValue === "allow" ? "APPROVED" : "DENIED";

    await answerCallbackQuery(config, queryId, `${emoji} ${action}`);
    await editMessageRemoveKeyboard(
      config,
      chatId,
      messageId,
      `${emoji} *${approval?.title || "Request"}* - ${action}\n\n${approval?.message || ""}`
    );
  } else {
    await answerCallbackQuery(config, queryId, "⚠️ Expired or already handled");
    await editMessageRemoveKeyboard(
      config,
      chatId,
      messageId,
      `⚠️ *Request Expired*\n\nThis request has already been handled or expired.`
    );
  }
}

async function handleCommand(config: TelegramConfig, text: string): Promise<boolean> {
  const cmd = text.split(" ")[0].toLowerCase();

  switch (cmd) {
    case "/ping":
      await sendMessage(config, "🏓 Pong! Listener is running.");
      return true;

    case "/status":
      await sendMessage(config, "🟢 *Telegram Listener*\n\nStatus: Running\nMode: Approvals only");
      return true;

    case "/help":
      await sendMessage(config,
        `🤖 *Claude Telegram Bridge*\n\n` +
        `This bot handles approval requests from Claude.\n\n` +
        `*Commands:*\n` +
        `/ping - Check if listener is alive\n` +
        `/status - Show status\n` +
        `/help - Show this message`
      );
      return true;

    default:
      return false;
  }
}

export async function startListener(): Promise<void> {
  const config = getTelegramConfig();
  if (!config) {
    console.error("❌ Telegram not configured. Run: bun run index.ts config <token> <chat_id>");
    process.exit(1);
  }

  console.log("🟢 Telegram listener started (approvals only)");
  await sendMessage(config, "🟢 *Listener Started*\n\nReady to handle approval requests.");

  let lastUpdateId = parseInt(getConfig("last_update_id") || "0");
  let lastCleanup = Date.now();
  const cleanupInterval = 60 * 60 * 1000; // 1 hour

  while (true) {
    const updates = await getUpdates(config, lastUpdateId + 1);

    for (const update of updates) {
      lastUpdateId = update.update_id;
      setConfig("last_update_id", lastUpdateId.toString());

      // Handle button presses
      if (update.callback_query) {
        const cq = update.callback_query;
        if (cq.message?.chat.id === parseInt(config.chat_id) && cq.data) {
          await handleCallbackQuery(
            config,
            cq.id,
            cq.data,
            cq.message.chat.id,
            cq.message.message_id
          );
        }
        continue;
      }

      // Handle commands
      if (update.message?.text?.startsWith("/") && update.message.chat.id === parseInt(config.chat_id)) {
        const handled = await handleCommand(config, update.message.text);
        if (!handled) {
          await sendMessage(config, "❓ Unknown command. Send /help for options.");
        }
      }
    }

    // Periodic cleanup
    if (Date.now() - lastCleanup > cleanupInterval) {
      const removed = cleanupOldApprovals(120); // Remove approvals older than 2 hours
      if (removed > 0) {
        console.log(`Cleaned up ${removed} old approvals`);
      }
      lastCleanup = Date.now();
    }
  }
}
