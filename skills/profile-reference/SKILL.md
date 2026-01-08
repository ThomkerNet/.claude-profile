---
name: profile-reference
description: Reference documentation for Claude profile features (MCP servers, router, Telegram, statusline). Load when you need detailed usage info for these systems.
---

# Profile Reference Documentation

Detailed documentation for Claude profile features. This is loaded on-demand when you need specifics.

---

## Multi-LLM Detailed Usage

### GitHub Copilot CLI (Primary for Peer Review)

Multi-model access via single CLI. **Preferred for all peer reviews and second opinions.**

**Available models:**
| Model | ID | Best for |
|-------|-----|----------|
| Claude Sonnet | `claude-sonnet-4.5` | Default, balanced |
| Claude Opus | `claude-opus-4.5` | Architecture, complex reasoning |
| GPT-5.1 | `gpt-5.1` | Security review, practical insights |
| Gemini Pro | `gemini-3-pro-preview` | Alternative perspective |

**When to use:**
- Peer review and second opinions (primary tool)
- Code review with fresh perspective
- Complex architectural decisions
- Shell commands and scripts
- Git/GitHub operations (PRs, issues, Actions)

**Usage:**
```bash
copilot -p "Review this code..."                           # Default model
copilot --model gpt-5.1 -p "Security review: ..."          # Specific model
copilot --model claude-opus-4.5 -p "Architecture review"   # Claude Opus
copilot --model gemini-3-pro-preview -p "Alternative take" # Gemini
```

**Note:** Requires GitHub Copilot Pro subscription.

### Gemini CLI (Multimodal Only)

Standalone Gemini for tasks requiring image/PDF input.

**When to use:**
- Multimodal tasks (images, diagrams, PDFs)
- Fallback if Copilot is unavailable

**Usage:**
```bash
gemini -p "Describe this image: [attach image]"
gemini -p "Analyze this PDF: [attach pdf]"
```

### Parallel Execution

When consulting multiple models, dispatch in parallel:
```
<function_calls>
<invoke name="Bash">copilot --model gpt-5.1 -p "..."</invoke>
<invoke name="Bash">copilot --model gemini-3-pro-preview -p "..."</invoke>
</function_calls>
```

---

## Telegram Integration

### Setup

1. Message @BotFather → `/newbot` → save token
2. Message bot, visit `https://api.telegram.org/bot<TOKEN>/getUpdates` → get chat ID
3. Configure: `bun run ~/.claude/hooks/telegram-bun/index.ts config <TOKEN> <CHAT_ID>`
4. Start listener: `bun run ~/.claude/hooks/telegram-bun/index.ts listen`

### API Usage

```typescript
import { requestApproval } from "~/.claude/hooks/telegram-bun/src/approval";

const result = await requestApproval({
  title: "Confirm Action",
  message: "Proceed with deployment?",
  options: [
    { label: "Yes", value: "yes" },
    { label: "No", value: "no" }
  ],
  timeout: 60000
});
```

### Bot Commands

| Command | Description |
|---------|-------------|
| `/ping` | Check if alive |
| `/status` | Show status |
| `/help` | Show help |

---

## MCP Servers Reference

### Context7 - Library Documentation

**Tools:**
- `mcp__context7__resolve-library-id` - Find library ID first
- `mcp__context7__query-docs` - Query with resolved ID

**When:** Verifying API syntax, best practices, breaking changes, code examples.

### Firecrawl - Web Scraping

**Preferred over WebFetch/WebSearch.**

| Tool | Use |
|------|-----|
| `firecrawl_scrape` | Single page |
| `firecrawl_search` | Web search |
| `firecrawl_map` | Discover URLs |
| `firecrawl_crawl` | Multi-page |
| `firecrawl_extract` | Structured data |
| `firecrawl_agent` | Autonomous (no URLs needed) |

### Puppeteer - Browser Automation

| Tool | Use |
|------|-----|
| `puppeteer_navigate` | Go to URL |
| `puppeteer_screenshot` | Capture |
| `puppeteer_click` | Click element |
| `puppeteer_fill` | Fill input |
| `puppeteer_evaluate` | Run JS |

**Resource:** `console://logs` for browser output.

### Memory - Knowledge Graph

**Store examples:**
```javascript
// User preference
create_entities([{
  name: "user",
  entityType: "person",
  observations: ["Prefers TypeScript", "Uses bun"]
}])

// Project pattern
create_entities([{
  name: "myproject",
  entityType: "project",
  observations: ["Docker Compose", "API on 6500"]
}])

// Connect them
create_relations([{from: "user", to: "myproject", relationType: "works_on"}])

// Add to existing
add_observations([{entityName: "user", contents: ["Prefers concise commits"]}])
```

---

## Claude Code Router

### Routing Table

| Route | Model | When |
|-------|-------|------|
| `default` | Sonnet | General coding |
| `background` | Haiku | Simple reads, formatting |
| `think` | Opus | Plan mode, architecture, security |
| `longContext` | Gemini 3 Pro | >60K tokens |
| `webSearch` | Gemini 3 Flash | Web search |

### Custom Routing

`~/.claude-code-router/custom-router.js` routes:
- Architecture/design/security → Opus
- Simple file ops, formatting, git → Haiku
- Explore agents → Haiku
- Plan agents → Opus

### Commands

```bash
cc                              # Start with routing (alias)
ccr code --dangerously-skip-permissions
/model gemini,gemini-3-pro-preview  # Switch mid-session
/router                         # Check status
ccr ui                          # Config UI
ccr restart                     # Restart after config changes
```

---

## Status Line

### Configuration

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/statusline.sh"
  }
}
```

**Must be object with `type` and `command`, not string.**

### Script Requirements

- Executable (`chmod +x`)
- Receives JSON on stdin: `model.display_name`, `workspace.current_dir`, `context_window.*`, `cost.*`
- Outputs single line (only first line shown)
- Handle missing fields with `jq // default`

### Session Labels

`~/.claude/.session-label` - set via `/cname`, shown in status line.
