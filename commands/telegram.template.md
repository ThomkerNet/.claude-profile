Start Telegram integration for this Claude Code session.

This starts the listener (if not already running) and registers your session with a unique ID (like `A3X`).

```bash
{{BUN_PATH}} run {{CLAUDE_HOME}}/hooks/telegram-bun/index.ts start-listener
```

```bash
{{BUN_PATH}} run {{CLAUDE_HOME}}/hooks/telegram-bun/index.ts register "$1"
```

Use `/telegram-end` when done. Send `/ping` via Telegram to check if listener is alive.
