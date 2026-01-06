# Claude Telegram Bridge (Simplified)

A minimal Telegram integration for Claude Code that handles approval requests via inline buttons.

## What This Does

When Claude needs user confirmation for an action, it sends a Telegram message with inline buttons. You tap a button, Claude gets the response and proceeds accordingly.

That's it. No sessions, no remote commands, no notifications.

## Setup

### 1. Create a Telegram Bot

1. Message [@BotFather](https://t.me/BotFather) on Telegram
2. Send `/newbot` and follow prompts
3. Save the bot token

### 2. Get Your Chat ID

1. Message your new bot (send anything)
2. Visit: `https://api.telegram.org/bot<TOKEN>/getUpdates`
3. Find `"chat":{"id":123456789}` - that's your chat ID

### 3. Configure

```bash
cd ~/.claude/hooks/telegram-bun
bun run index.ts config <BOT_TOKEN> <CHAT_ID>
```

Or create `~/.claude/hooks/telegram-config.json`:
```json
{
  "bot_token": "123456789:ABCdefGHI...",
  "chat_id": "987654321"
}
```

### 4. Start the Listener

```bash
bun run index.ts listen
```

Keep this running in a terminal or as a background service.

## Usage

### From Your Code

```typescript
import { requestApproval } from "~/.claude/hooks/telegram-bun/src/approval";

const result = await requestApproval({
  title: "Confirm Action",
  message: "Delete all log files?",
  options: [
    { label: "✅ Yes", value: "yes" },
    { label: "❌ No", value: "no" }
  ],
  timeout: 60000  // 60 seconds
});

if (result.approved) {
  // User tapped Yes (first option)
} else if (result.timedOut) {
  // No response within timeout
} else {
  // User tapped No (or error)
}
```

### CLI Commands

| Command | Description |
|---------|-------------|
| `bun run index.ts config <token> <chat_id>` | Configure bot credentials |
| `bun run index.ts listen` | Start the approval listener |
| `bun run index.ts status` | Show configuration status |

### Telegram Commands

| Command | Description |
|---------|-------------|
| `/ping` | Check if listener is alive |
| `/status` | Show listener status |
| `/help` | Show help |

## Architecture

```
┌─────────────────────────────────────┐
│  Your Tool (e.g., bw-wrapper.ts)    │
│  Calls requestApproval()            │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  approval.ts                        │
│  - Creates DB record                │
│  - Sends Telegram message           │
│  - Polls DB for response            │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Telegram (inline buttons)          │
│  User taps Allow/Deny               │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  listener.ts                        │
│  - Receives button callback         │
│  - Updates DB with response         │
│  - Edits message to show result     │
└─────────────────────────────────────┘
```

## Database

SQLite database at `~/.claude/hooks/telegram-bun/telegram.db` with 2 tables:

- `config` - Key/value settings (bot_token, chat_id, last_update_id)
- `approvals` - Approval requests and their status

## Files

```
telegram-bun/
├── index.ts          # Entry point
├── src/
│   ├── cli.ts        # CLI command handler
│   ├── db.ts         # SQLite database layer
│   ├── listener.ts   # Telegram long-polling listener
│   └── approval.ts   # requestApproval() function
├── telegram.db       # SQLite database (gitignored)
└── old/              # Archived previous complex version
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `APPROVAL_TIMEOUT` | `60000` | Default approval timeout in milliseconds |

## Previous Version

The `old/` directory contains the previous complex version with:
- Multi-session support
- Instruction queuing (remote commands to Claude)
- Question/answer system
- Notifications
- Idle detection
- Multiple hook scripts

This was simplified because:
1. Only one Claude instance typically runs at a time
2. Remote commanding wasn't being used
3. Notifications weren't being used
4. Complexity made maintenance harder
