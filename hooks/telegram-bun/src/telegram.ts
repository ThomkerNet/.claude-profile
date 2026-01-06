import {
  db,
  getConfig,
  setConfig,
  getAllSessions,
  getDefaultSession,
  setDefaultSession,
  addInstruction,
  answerQuestion,
  getSession,
  cleanupStaleSessions,
  cleanupDeadProcessSessions,
} from "./db";

const BOT_TOKEN = getConfig("bot_token");
const CHAT_ID = getConfig("chat_id");

const API_BASE = `https://api.telegram.org/bot${BOT_TOKEN}`;

export async function sendMessage(text: string): Promise<number | null> {
  if (!BOT_TOKEN || !CHAT_ID) {
    console.error("Missing bot_token or chat_id in config");
    return null;
  }

  try {
    const response = await fetch(`${API_BASE}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: CHAT_ID,
        text,
        parse_mode: "Markdown",
      }),
    });

    const data = await response.json();
    return data.ok ? data.result.message_id : null;
  } catch (error) {
    console.error("Failed to send message:", error);
    return null;
  }
}

/**
 * Reply to a specific message
 */
export async function replyToMessage(replyToMessageId: number, text: string): Promise<number | null> {
  if (!BOT_TOKEN || !CHAT_ID) {
    return null;
  }

  try {
    const response = await fetch(`${API_BASE}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: CHAT_ID,
        text,
        parse_mode: "Markdown",
        reply_to_message_id: replyToMessageId,
      }),
    });

    const data = await response.json();
    return data.ok ? data.result.message_id : null;
  } catch (error) {
    console.error("Failed to reply to message:", error);
    return null;
  }
}

interface InlineButton {
  text: string;
  callback_data: string;
}

/**
 * Send a message with inline keyboard buttons
 */
export async function sendMessageWithButtons(
  text: string,
  buttons: InlineButton[][]
): Promise<boolean> {
  if (!BOT_TOKEN || !CHAT_ID) {
    console.error("Missing bot_token or chat_id in config");
    return false;
  }

  try {
    const response = await fetch(`${API_BASE}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: CHAT_ID,
        text,
        parse_mode: "Markdown",
        reply_markup: {
          inline_keyboard: buttons,
        },
      }),
    });

    const data = await response.json();
    return data.ok === true;
  } catch (error) {
    console.error("Failed to send message with buttons:", error);
    return false;
  }
}

/**
 * Answer a callback query (acknowledge button press)
 */
async function answerCallbackQuery(callbackQueryId: string, text?: string): Promise<void> {
  try {
    await fetch(`${API_BASE}/answerCallbackQuery`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        callback_query_id: callbackQueryId,
        text,
      }),
    });
  } catch (error) {
    console.error("Failed to answer callback query:", error);
  }
}

/**
 * Edit a message to remove inline keyboard after button press
 */
async function editMessageRemoveKeyboard(chatId: number, messageId: number, newText: string): Promise<void> {
  try {
    await fetch(`${API_BASE}/editMessageText`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        message_id: messageId,
        text: newText,
        parse_mode: "Markdown",
      }),
    });
  } catch (error) {
    console.error("Failed to edit message:", error);
  }
}

/**
 * React to a message with an emoji (thumbs up by default)
 */
export async function reactToMessage(messageId: number, emoji: string = "👍"): Promise<boolean> {
  if (!BOT_TOKEN || !CHAT_ID) {
    return false;
  }

  try {
    const response = await fetch(`${API_BASE}/setMessageReaction`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: CHAT_ID,
        message_id: messageId,
        reaction: [{ type: "emoji", emoji }],
      }),
    });
    const data = await response.json();
    return data.ok === true;
  } catch (error) {
    console.error("Failed to react to message:", error);
    return false;
  }
}

interface TelegramUpdate {
  update_id: number;
  message?: {
    message_id: number;
    text?: string;
    chat: { id: number };
    from?: { username?: string };
  };
  callback_query?: {
    id: string;
    data?: string;
    message?: {
      chat: { id: number };
      message_id: number;
    };
    from?: { username?: string };
  };
}

async function getUpdates(offset: number): Promise<TelegramUpdate[]> {
  try {
    const response = await fetch(
      `${API_BASE}/getUpdates?offset=${offset}&timeout=30`
    );
    const data = await response.json();
    return data.ok ? data.result : [];
  } catch (error) {
    console.error("Failed to get updates:", error);
    return [];
  }
}

async function handleCommand(text: string, messageId: number): Promise<boolean> {
  const defaultSession = getDefaultSession();

  // /status
  if (text === "/status") {
    const sessions = getAllSessions() as any[];
    if (sessions.length === 0) {
      sendMessage("📋 *No active sessions*\n\nStart Claude Code to create a session.");
    } else {
      const lines = sessions.map((s) => {
        const isDefault = s.id === defaultSession ? " \\*" : "";
        return `\`${s.id}\`${isDefault} - ${s.description}`;
      });
      const paused = getConfig("paused") === "true" ? "\n\n⏸️ Notifications paused" : "";
      sendMessage(`📋 *Active Sessions:*\n\n${lines.join("\n")}${paused}\n\n_\\* = default session_`);
    }
    return true;
  }

  // /switch ABC
  const switchMatch = text.match(/^\/switch\s+([A-Z0-9]{3})$/i);
  if (switchMatch) {
    const target = switchMatch[1].toUpperCase();
    if (setDefaultSession(target)) {
      sendMessage(`✅ Switched to session \`${target}\``);
    } else {
      sendMessage(`❌ Session \`${target}\` not found`);
    }
    return true;
  }

  // /abort ABC
  const abortMatch = text.match(/^\/abort\s+([A-Z0-9]{3})$/i);
  if (abortMatch) {
    const target = abortMatch[1].toUpperCase();
    if (getSession(target)) {
      db.run("UPDATE sessions SET status = 'aborted' WHERE id = ?", [target]);
      addInstruction(target, "ABORT_REQUESTED");
      sendMessage(`🛑 Abort signal sent to session \`${target}\``);
    } else {
      sendMessage(`❌ Session \`${target}\` not found`);
    }
    return true;
  }

  // /tell ABC instruction OR /tell instruction
  const tellMatch = text.match(/^\/tell\s+(?:([A-Z0-9]{3})\s+)?(.+)$/is);
  if (tellMatch) {
    const target = tellMatch[1]?.toUpperCase() || defaultSession;
    const instruction = tellMatch[2];

    if (!target) {
      sendMessage("❌ No default session. Use `/tell ABC instruction`");
      return true;
    }

    if (getSession(target)) {
      const queuedMsgId = await replyToMessage(messageId, `📨 Instruction queued for \`${target}\``);
      addInstruction(target, instruction, messageId, queuedMsgId ?? undefined);
    } else {
      sendMessage(`❌ Session \`${target}\` not found`);
    }
    return true;
  }

  // /pause
  if (text === "/pause") {
    setConfig("paused", "true");
    sendMessage("⏸️ Notifications paused. Send /resume to continue.");
    return true;
  }

  // /resume
  if (text === "/resume") {
    setConfig("paused", "false");
    sendMessage("▶️ Notifications resumed.");
    return true;
  }

  // /help
  if (text === "/help") {
    sendMessage(`🤖 *Claude Code Telegram Commands*

*Session Management:*
/status - List active sessions
/switch ABC - Switch default session
/abort ABC - Abort a session
/cleanup - Remove dead sessions

*Instructions:*
/tell ABC do something - Send instruction to session
/tell do something - Send to default session
! do something - Shorthand for /tell

*Notifications:*
/pause - Pause all notifications
/resume - Resume notifications

*Health:*
/ping - Check if listener is alive

*Replying to Claude:*
- Reply directly for default session
- Prefix with session ID: \`ABC: your reply\``);
    return true;
  }

  // /ping - health check
  if (text === "/ping") {
    const sessions = getAllSessions() as any[];
    const uptime = process.uptime();
    const hours = Math.floor(uptime / 3600);
    const minutes = Math.floor((uptime % 3600) / 60);
    sendMessage(`🏓 *Pong!*\n\nListener uptime: ${hours}h ${minutes}m\nActive sessions: ${sessions.length}`);
    return true;
  }

  // /cleanup - remove dead sessions
  if (text === "/cleanup") {
    const deadRemoved = cleanupDeadProcessSessions();
    const staleRemoved = cleanupStaleSessions(24);

    if (deadRemoved.length === 0 && staleRemoved === 0) {
      sendMessage("🧹 No stale sessions to clean up.");
    } else {
      const parts = [];
      if (deadRemoved.length > 0) {
        parts.push(`Dead processes: ${deadRemoved.map(id => `\`${id}\``).join(", ")}`);
      }
      if (staleRemoved > 0) {
        parts.push(`Old sessions (>24h): ${staleRemoved}`);
      }
      sendMessage(`🧹 *Cleanup complete*\n\n${parts.join("\n")}`);
    }
    return true;
  }

  return false;
}

/**
 * Handle callback queries from inline buttons
 * Format: action:sessionId:value (e.g., "answer:ABC:yes")
 */
async function handleCallbackQuery(
  callbackQueryId: string,
  data: string,
  chatId: number,
  messageId: number
): Promise<void> {
  const parts = data.split(":");
  const action = parts[0];
  const sessionId = parts[1];
  const value = parts.slice(2).join(":");

  if (action === "answer") {
    if (getSession(sessionId)) {
      if (answerQuestion(sessionId, value)) {
        await answerCallbackQuery(callbackQueryId, `Sent: ${value}`);
        await editMessageRemoveKeyboard(
          chatId,
          messageId,
          `✅ *[${sessionId}] Answered:* ${value}`
        );
      } else {
        await answerCallbackQuery(callbackQueryId, "No pending question");
        await editMessageRemoveKeyboard(
          chatId,
          messageId,
          `⚠️ *[${sessionId}]* No pending question to answer`
        );
      }
    } else {
      await answerCallbackQuery(callbackQueryId, "Session not found");
    }
  } else {
    await answerCallbackQuery(callbackQueryId, "Unknown action");
  }
}

async function handleMessage(text: string, messageId: number): Promise<void> {
  const defaultSession = getDefaultSession();

  // Check for ! prefix (instruction shorthand)
  // Session IDs use chars: ABCDEFGHJKLMNPQRSTUVWXYZ23456789 (no I, O, 0, 1)
  const instructionMatch = text.match(/^!\s*(?:([ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{3})\s+)?(.+)$/s);
  if (instructionMatch) {
    const explicitSession = instructionMatch[1]?.toUpperCase();
    const instruction = instructionMatch[2];

    // If explicit session given, it must exist
    if (explicitSession) {
      if (getSession(explicitSession)) {
        const queuedMsgId = await replyToMessage(messageId, `📨 Instruction queued for \`${explicitSession}\``);
        addInstruction(explicitSession, instruction, messageId, queuedMsgId ?? undefined);
      } else {
        sendMessage(`❌ Session \`${explicitSession}\` not found`);
      }
      return;
    }

    // No explicit session - use default
    if (defaultSession && getSession(defaultSession)) {
      const queuedMsgId = await replyToMessage(messageId, `📨 Instruction queued for \`${defaultSession}\``);
      addInstruction(defaultSession, instruction, messageId, queuedMsgId ?? undefined);
    } else {
      sendMessage("❌ No default session. Use `!ABC instruction`");
    }
    return;
  }

  // Check for session prefix: ABC: message
  // Session IDs use chars: ABCDEFGHJKLMNPQRSTUVWXYZ23456789 (no I, O, 0, 1)
  // Only match this restricted set to avoid false positives on words like "ASK:", "THE:", etc.
  const sessionMatch = text.match(/^([ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{3}):\s*(.+)$/s);
  if (sessionMatch) {
    const target = sessionMatch[1].toUpperCase();
    const message = sessionMatch[2];

    if (getSession(target)) {
      if (answerQuestion(target, message)) {
        // Answered a pending question
      } else {
        // No pending question, treat as instruction
        const queuedMsgId = await replyToMessage(messageId, `📨 Instruction queued for \`${target}\``);
        addInstruction(target, message, messageId, queuedMsgId ?? undefined);
      }
      return;
    }
    // Session doesn't exist - fall through to default session handling
  }

  // Default session reply
  if (defaultSession && getSession(defaultSession)) {
    if (!answerQuestion(defaultSession, text)) {
      // No pending question, treat as instruction
      const queuedMsgId = await replyToMessage(messageId, `📨 Instruction queued for \`${defaultSession}\``);
      addInstruction(defaultSession, text, messageId, queuedMsgId ?? undefined);
    }
  } else {
    sendMessage("❓ No active session. Start Claude Code first or use /status to check.");
  }
}

export async function startPolling(): Promise<void> {
  if (!BOT_TOKEN || !CHAT_ID) {
    console.error("Missing bot_token or chat_id. Run: claude-telegram config <token> <chat_id>");
    process.exit(1);
  }

  console.log("🟢 Telegram listener started");
  await sendMessage("🟢 *Telegram Listener Started*\n\nSend /help for available commands.");

  let lastUpdateId = parseInt(getConfig("last_update_id") || "0");
  let errorBackoff = 1000; // Start with 1 second
  const maxBackoff = 60000; // Max 60 seconds
  let lastCleanup = Date.now();
  const cleanupInterval = 60 * 60 * 1000; // Run cleanup every hour

  while (true) {
    try {
      const updates = await getUpdates(lastUpdateId + 1);

      // Reset backoff on success
      errorBackoff = 1000;

      for (const update of updates) {
        lastUpdateId = update.update_id;
        setConfig("last_update_id", lastUpdateId.toString());

        // Handle callback queries (inline button presses)
        if (update.callback_query) {
          const cq = update.callback_query;
          if (cq.message?.chat.id === parseInt(CHAT_ID!) && cq.data) {
            await handleCallbackQuery(
              cq.id,
              cq.data,
              cq.message.chat.id,
              cq.message.message_id
            );
          }
          continue;
        }

        // Handle regular messages
        if (update.message?.text && update.message.chat.id === parseInt(CHAT_ID!)) {
          const text = update.message.text;
          const messageId = update.message.message_id;

          if (text.startsWith("/")) {
            if (!(await handleCommand(text, messageId))) {
              sendMessage("❓ Unknown command. Send /help for options.");
            }
          } else {
            handleMessage(text, messageId);
          }
        }
      }

      // Periodic cleanup of dead sessions
      if (Date.now() - lastCleanup > cleanupInterval) {
        const removed = cleanupDeadProcessSessions();
        if (removed.length > 0) {
          console.log(`Cleaned up dead sessions: ${removed.join(", ")}`);
        }
        lastCleanup = Date.now();
      }
    } catch (error) {
      console.error(`Polling error (retrying in ${errorBackoff / 1000}s):`, error);
      await Bun.sleep(errorBackoff);

      // Exponential backoff with max cap
      errorBackoff = Math.min(errorBackoff * 2, maxBackoff);
    }
  }
}
