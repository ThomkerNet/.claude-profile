---
name: zupdatetknmcpservers
description: Sync MCP servers from TKNet-MCPServer repo to claude-profile mcp-servers.json
---

# Sync TKN MCP Servers to Claude Profile

Update `~/.claude-profile/mcp-servers.json` with all deployed MCP servers from the TKNet-MCPServer compose.yaml.

## Critical: Source of Truth

**THE ONLY SOURCE OF TRUTH FOR PORTS IS: `~/git-bnx/TKN/TKNet-MCPServer/compose.yaml`**

- ❌ DO NOT use README.md for port numbers (it's often outdated)
- ✅ DO parse actual port mappings from compose.yaml
- ✅ DO use README.md ONLY for descriptions (matching by server name)

## Task

1. **Parse compose.yaml for deployed servers**
   - Read `~/git-bnx/TKN/TKNet-MCPServer/compose.yaml`
   - Find all uncommented lines matching: `- "XXXX:XXXX"  # server-name`
   - Extract port (XXXX) and server name from comment
   - Skip any line starting with `#` (commented out)

2. **Read current MCP configuration**
   - Read `~/.claude-profile/mcp-servers.json`

3. **Update/fix ALL TKN server entries**
   - For each server in compose.yaml:
     - If missing from mcp-servers.json: ADD it
     - If exists but wrong port: UPDATE the URL
     - Preserve all other fields (description, etc.)

4. **Remove orphaned entries**
   - If a TKN/BNX server exists in mcp-servers.json but NOT in compose.yaml:
     - Remove it (not deployed anymore)

5. **Get descriptions**
   - Try README.md table, matching by server NAME (not port)
   - Fallback to generic: `{service-name} management`

6. **Write updated mcp-servers.json**
   - Preserve non-TKN servers (memory, context7, puppeteer, etc.)
   - Write the complete updated JSON

7. **Report changes**
   - Added: X servers
   - Updated: Y servers
   - Removed: Z servers
   - Unchanged: N servers

## Parsing Logic

### Extract from compose.yaml

```bash
# Read the ports section (lines 70-99)
# Match pattern: - "8200:8200"  # tkn-cloudflare
# Extract: port=8200, name=tkn-cloudflare
```

**Example lines:**
```yaml
- "8200:8200"  # tkn-cloudflare    → port=8200, name=tkn-cloudflare
- "8221:8221"  # tkn-media         → port=8221, name=tkn-media
# - "8101:8101"  # bnx-azure        → SKIP (commented out)
```

### Get descriptions from README

```bash
# Read README.md table (lines 44-66)
# Match by server NAME (not port!)
# Example: | tkn-cloudflare | 8200 | DNS and zone management |
#          ^^^^^^^^^^^^^^^^        ^^^^^^^^^^^^^^^^^^^^^^^^
#          name (match this)       description (extract this)
```

**Important:** Match by column 1 (server name), extract column 3 (description). Ignore column 2 (port) as it may be outdated.

### Fallback description

If not in README:
- `tkn-{service}` → `{service} management`
- `bnx-{service}` → `{service} management (BoroughNexus business)`

## Output Format

Each server entry uses `npx -y mcp-remote` with Tailscale HTTPS:
```json
{
  "name": "tkn-cloudflare",
  "command": "npx -y mcp-remote https://mcp-<hostname>.gate-hexatonic.ts.net/sse",
  "description": "DNS and zone management (Tailscale HTTPS)"
}
```

**Tailscale hostname mapping:** The hostname in the URL is configured in Tailscale serve config. For existing servers, **preserve the current URL from mcp-servers.json**. For NEW servers, generate a proposed URL following the common pattern:

1. Strip `tkn-` or `bnx-` prefix from compose service name
2. Prepend `mcp-`
3. Form: `https://mcp-{stripped-name}.gate-hexatonic.ts.net/sse`

Example: `tkn-media` → `https://mcp-media.gate-hexatonic.ts.net/sse`

Mark the proposed URL as **UNVERIFIED** in the report. After writing mcp-servers.json, verify with:
```bash
curl -sf -o /dev/null -w "%{http_code}" https://mcp-{name}.gate-hexatonic.ts.net/sse
```
If the health check fails (non-200), flag it for operator to configure Tailscale serve for port XXXX.

## Important Rules

1. **Only update TKN/BNX servers** - Don't touch memory, context7, puppeteer, sequential-thinking
2. **Match by name, not port** - When looking up descriptions in README
3. **Preserve existing URLs** - TKN servers use Tailscale HTTPS hostnames configured outside compose.yaml
4. **Skip commented lines** - Lines starting with `#` in compose.yaml
5. **Remove orphans** - TKN/BNX servers in JSON but not in compose.yaml
6. **Preserve order** - Keep non-TKN servers at the top, TKN servers alphabetically
7. **Use command field** - Format: `"command": "npx -y mcp-remote <URL>"` (not transport/url fields)

## Example Execution

**Input: compose.yaml**
```yaml
ports:
  - "8200:8200"  # tkn-cloudflare
  - "8221:8221"  # tkn-media
  # - "8100:8100"  # bnx-cloudflare (commented - skip)
```

**Input: README.md**
```markdown
| tkn-cloudflare | 8200 | DNS and zone management |
| tkn-media | 8207 | Plex, Jellyfin |  ← WRONG PORT (ignore)
```

**Input: mcp-servers.json (before)**
```json
{
  "servers": [
    {"name": "memory", "command": "..."},
    {"name": "tkn-cloudflare", "command": "npx -y mcp-remote https://mcp-tkn-bnx-cloudflare.gate-hexatonic.ts.net/sse", "description": "DNS and zone management"}
  ]
}
```

**Output: mcp-servers.json (after)** (tkn-media is new in compose.yaml)
```json
{
  "servers": [
    {"name": "memory", "command": "..."},
    {"name": "tkn-cloudflare", "command": "npx -y mcp-remote https://mcp-tkn-bnx-cloudflare.gate-hexatonic.ts.net/sse", "description": "DNS and zone management"},
    {"name": "tkn-media", "command": "npx -y mcp-remote https://mcp-media.gate-hexatonic.ts.net/sse", "description": "Plex, Jellyfin (Tailscale HTTPS)"}
  ]
}
```

**Report:**
- Added: 1 server (tkn-media, port 8221, UNVERIFIED URL - verifying...)
  - `curl -sf https://mcp-media.gate-hexatonic.ts.net/sse` → 200 OK (verified)
- Unchanged: 1 server (tkn-cloudflare)

## Implementation Steps

1. Use Read tool on `~/git-bnx/TKN/TKNet-MCPServer/compose.yaml` (lines 70-99)
2. Use Grep to extract port lines: `pattern='^\s*- "[0-9]+:[0-9]+".*#'`
3. Parse each line to get port and name
4. Use Read tool on `~/git-bnx/TKN/TKNet-MCPServer/README.md` (lines 44-70)
5. Parse table to map server names → descriptions
6. Use Read tool on `~/.claude-profile/mcp-servers.json`
7. Build updated server list:
   - Keep all non-TKN/BNX servers as-is
   - Add/update TKN/BNX servers from compose.yaml
8. Use Write tool to save updated `~/.claude-profile/mcp-servers.json`
9. Report what changed
