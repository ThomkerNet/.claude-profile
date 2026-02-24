---
name: zupdatetknmcpservers
description: Sync MCP servers from TKNet-MCPServer repo to claude-profile mcp-servers.json
---

# Sync TKN MCP Servers to Claude Profile

Update `~/.claude-profile/mcp-servers.json` with all deployed MCP servers.

## Critical: Source of Truth

**THE ONLY SOURCE OF TRUTH IS: `~/git-bnx/TKN/TKNet-MCPServer/CLAUDE.md` — the "MCP Server Connectivity" table**

All MCP servers are deployed as **standalone stacks** (the monolith was decommissioned). The `compose.yaml` in TKNet-MCPServer is for the legacy monolith mode and lists servers that are NOT individually deployed — do not use it.

- ✅ **DO** parse the connectivity table from `CLAUDE.md` (section: "MCP Server Connectivity")
- ✅ **DO** use the exact URLs from that table — they are verified Tailscale HTTPS endpoints
- ❌ DO NOT use `compose.yaml` for the server list (monolith mode, not standalone)
- ❌ DO NOT use README.md for URLs (often outdated)

## Task

1. **Parse CLAUDE.md for deployed servers**
   - Read `~/git-bnx/TKN/TKNet-MCPServer/CLAUDE.md`
   - Find the "MCP Server Connectivity" section
   - Parse the table: `| Server | Stack | HTTPS URL |`
   - Extract server name (column 1) and HTTPS URL (column 3) for each row
   - Strip backticks from the URL value

2. **Read current MCP configuration**
   - Read `~/.claude-profile/mcp-servers.json`

3. **Update/fix ALL TKN/BNX server entries**
   - For each server in CLAUDE.md connectivity table:
     - If missing from mcp-servers.json: ADD it with the verified URL
     - If exists with correct URL: keep unchanged
     - If exists with wrong URL: UPDATE to the CLAUDE.md URL
   - Preserve existing descriptions where present; use fallback for new servers

4. **Remove orphaned entries**
   - If a TKN/BNX server exists in mcp-servers.json but NOT in CLAUDE.md connectivity table: remove it

5. **Get descriptions**
   - Preserve existing descriptions from mcp-servers.json
   - For new servers: check README.md table (match by server name, extract description column)
   - Fallback: `{service-name} management`

6. **Write updated mcp-servers.json**
   - Preserve non-TKN/BNX servers (memory, context7, puppeteer, sequential-thinking) exactly as-is
   - Write TKN/BNX servers alphabetically after them

7. **Report changes**
   - Added: X servers
   - Updated: Y servers (URL changed)
   - Removed: Z servers (not in CLAUDE.md anymore)
   - Unchanged: N servers

## Parsing Logic

### Extract from CLAUDE.md

```
# Find the MCP Server Connectivity section, then parse table rows:
# | tkn-action1 | mcp-action1 | `https://mcp-action1.gate-hexatonic.ts.net/mcp` |
#   ^^^^^^^^^^^                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#   server name (col 1)           URL (col 3, strip backticks)
```

The table looks like:
```markdown
| Server | Stack | HTTPS URL |
|--------|-------|-----------|
| tkn-action1 | mcp-action1 | `https://mcp-action1.gate-hexatonic.ts.net/mcp` |
| tkn-aipeer | mcp-aipeer | `https://mcp-aipeer.gate-hexatonic.ts.net/mcp` |
...
```

### Fallback description

If not in README:
- `tkn-{service}` → `{service} management`
- `bnx-{service}` → `{service} management (BoroughNexus)`

## Output Format

Each server entry:
```json
{
  "name": "tkn-action1",
  "url": "https://mcp-action1.gate-hexatonic.ts.net/mcp",
  "transport": "streamable-http",
  "description": "Action1 RMM endpoint management"
}
```

## Important Rules

1. **Only update TKN/BNX servers** — don't touch memory, context7, puppeteer, sequential-thinking
2. **CLAUDE.md is canonical** — URLs in CLAUDE.md are verified; trust them
3. **Preserve existing descriptions** — don't overwrite good descriptions with generic fallbacks
4. **Remove orphans** — TKN/BNX servers in JSON but not in CLAUDE.md connectivity table
5. **Alphabetical order** — TKN/BNX servers sorted by name after the non-TKN servers
6. **Use transport/url fields** — `"url": "<URL>", "transport": "streamable-http"` (not stdio command)

## Example Execution

**Input: CLAUDE.md connectivity table**
```markdown
| tkn-bnx-cloudflare | mcp-tkn-bnx-cloudflare | `https://mcp-tkn-bnx-cloudflare.gate-hexatonic.ts.net/mcp` |
| tkn-komodo | mcp-komodo | `https://mcp-komodo.gate-hexatonic.ts.net/mcp` |
```

**Input: mcp-servers.json (before)**
```json
{
  "servers": [
    {"name": "memory", "command": "..."},
    {"name": "tkn-bnx-cloudflare", "url": "https://mcp-tkn-bnx-cloudflare.gate-hexatonic.ts.net/mcp", "transport": "streamable-http", "description": "Cloudflare DNS, Zero Trust"},
    {"name": "tkn-old-server", "url": "https://mcp-old.gate-hexatonic.ts.net/mcp", "transport": "streamable-http"}
  ]
}
```

**Output: mcp-servers.json (after)**
```json
{
  "servers": [
    {"name": "memory", "command": "..."},
    {"name": "tkn-bnx-cloudflare", "url": "https://mcp-tkn-bnx-cloudflare.gate-hexatonic.ts.net/mcp", "transport": "streamable-http", "description": "Cloudflare DNS, Zero Trust"},
    {"name": "tkn-komodo", "url": "https://mcp-komodo.gate-hexatonic.ts.net/mcp", "transport": "streamable-http", "description": "komodo management"}
  ]
}
```

**Report:**
- Added: 1 server (tkn-komodo)
- Removed: 1 server (tkn-old-server — not in CLAUDE.md)
- Unchanged: 1 server (tkn-bnx-cloudflare)

## Implementation Steps

1. Read `~/git-bnx/TKN/TKNet-MCPServer/CLAUDE.md`
2. Find the "MCP Server Connectivity" section and parse the table rows
3. Extract: server name (col 1), URL (col 3, strip backticks)
4. Read `~/.claude-profile/mcp-servers.json`
5. Read `~/git-bnx/TKN/TKNet-MCPServer/README.md` for descriptions (match by server name)
6. Build updated server list:
   - Keep all non-TKN/BNX servers as-is
   - Add/update TKN/BNX servers from CLAUDE.md table
   - Remove TKN/BNX servers not in CLAUDE.md table
7. Write updated `~/.claude-profile/mcp-servers.json`
8. Report what changed
