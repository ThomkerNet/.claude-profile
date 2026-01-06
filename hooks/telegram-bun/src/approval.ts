/**
 * Simplified Telegram Approval System
 *
 * Single purpose: Request user approval via Telegram inline buttons.
 * No sessions, no instructions, no questions.
 *
 * Usage:
 *   import { requestApproval } from "./approval";
 *
 *   const result = await requestApproval({
 *     title: "Confirm Action",
 *     message: "Delete all logs?",
 *     options: [
 *       { label: "✅ Yes", value: "yes" },
 *       { label: "❌ No", value: "no" }
 *     ],
 *     timeout: 60000
 *   });
 *
 *   if (result.approved) {
 *     // User selected first option (value === "yes")
 *   }
 */

import { existsSync, readFileSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import {
  getConfig,
  createApproval,
  getApprovalStatus,
  setApprovalTelegramMessageId,
  expireApproval,
  type ApprovalOption,
} from "./db";

const CONFIG_FILE = join(homedir(), ".claude", "hooks", "telegram-config.json");
const DEFAULT_TIMEOUT = 60000;
const POLL_INTERVAL = 1000;

interface TelegramConfig {
  bot_token: string;
  chat_id: string;
}

export interface ApprovalRequest {
  title: string;
  message: string;
  options: ApprovalOption[];
  timeout?: number;
  category?: string;
}

export interface ApprovalResult {
  approved: boolean;
  value?: string;
  timedOut?: boolean;
  error?: string;
}

function getTelegramConfig(): TelegramConfig | null {
  // Try JSON config file first
  if (existsSync(CONFIG_FILE)) {
    try {
      return JSON.parse(readFileSync(CONFIG_FILE, "utf-8"));
    } catch {
      // Fall through to DB config
    }
  }

  // Fall back to DB config
  const botToken = getConfig("bot_token");
  const chatId = getConfig("chat_id");
  if (botToken && chatId) {
    return { bot_token: botToken, chat_id: chatId };
  }

  return null;
}

export async function requestApproval(request: ApprovalRequest): Promise<ApprovalResult> {
  const config = getTelegramConfig();
  if (!config) {
    return { approved: false, error: "Telegram not configured" };
  }

  const category = request.category || "general";
  const timeout = request.timeout || DEFAULT_TIMEOUT;

  // Create approval record
  const approvalId = createApproval(
    category,
    request.title,
    request.message,
    request.options
  );

  // Build inline keyboard
  const buttons = request.options.map(opt => ({
    text: opt.label,
    callback_data: `approval:${approvalId}:${opt.value}`
  }));

  // Arrange buttons: up to 2 per row
  const keyboard: { text: string; callback_data: string }[][] = [];
  if (buttons.length <= 2) {
    keyboard.push(buttons);
  } else {
    keyboard.push(buttons.slice(0, 2));
    keyboard.push(buttons.slice(2, 4));
  }

  // Format message
  const fullMessage =
    `*${request.title}*\n\n` +
    `${request.message}\n\n` +
    `_Expires in ${Math.round(timeout / 1000)}s_`;

  // Send to Telegram
  let telegramMessageId: number | null = null;
  try {
    const response = await fetch(
      `https://api.telegram.org/bot${config.bot_token}/sendMessage`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: config.chat_id,
          text: fullMessage,
          parse_mode: "Markdown",
          reply_markup: { inline_keyboard: keyboard }
        })
      }
    );

    const data = await response.json() as { ok: boolean; result?: { message_id: number } };
    if (data.ok && data.result) {
      telegramMessageId = data.result.message_id;
      setApprovalTelegramMessageId(approvalId, telegramMessageId);
    } else {
      return { approved: false, error: "Failed to send Telegram message" };
    }
  } catch (error: any) {
    return { approved: false, error: error.message };
  }

  // Poll for response
  const startTime = Date.now();
  while (Date.now() - startTime < timeout) {
    await Bun.sleep(POLL_INTERVAL);

    const approval = getApprovalStatus(approvalId);
    if (approval?.status === "responded") {
      return {
        approved: approval.response_value === "allow",
        value: approval.response_value ?? undefined
      };
    }
  }

  // Timeout - mark as expired
  expireApproval(approvalId);

  // Edit message to show expiration
  if (telegramMessageId) {
    try {
      await fetch(`https://api.telegram.org/bot${config.bot_token}/editMessageText`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: config.chat_id,
          message_id: telegramMessageId,
          text: `⏰ *${request.title}* - EXPIRED\n\n${request.message}\n\n_No response received_`,
          parse_mode: "Markdown"
        })
      });
    } catch {
      // Best effort
    }
  }

  return { approved: false, timedOut: true };
}

/**
 * Handle callback from Telegram button press.
 * Called by the listener when it receives an approval:* callback.
 */
export { respondToApproval } from "./db";
export { getApproval } from "./db";
