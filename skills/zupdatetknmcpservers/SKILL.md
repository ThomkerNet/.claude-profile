---
name: zupdatetknmcpservers
description: Sync MCP servers from TKNet-MCPServer repo to claude-profile mcp-servers.json
---

# Sync TKN MCP Servers to Claude Profile

Ensure all deployed MCP servers from `~/git-bnx/TKN/TKNet-MCPServer` are configured in this Claude profile's `mcp-servers.json`.

## Task - Fully Dynamic Discovery

1. **Find repositories** - Locate MCP server repos
   - Search for `TKNet-MCPServer` or `TKNet-Docker-Stacks` in `~/git-bnx/TKN/`
   - Use Glob to find compose.yaml files: `~/git-bnx/TKN/**/compose.yaml`

2. **Parse deployed servers from compose.yaml** - Dynamically extract all uncommented port mappings
   - Use Grep to find lines matching: `^\s*- "(\d+):(\d+)"\s*#\s*(.+)$`
   - Extract: port number (left side), server name (from comment after #)
   - Skip commented lines (starting with #)
   - Example: `- "8200:8200"  # tkn-cloudflare` → port=8200, name=tkn-cloudflare

3. **Discover descriptions** - Try multiple sources in order:
   - **Option A:** Parse README.md server table if it exists
     - Use Grep to find table with format: `| server-name | port | description |`
     - Match by server NAME (not port)
   - **Option B:** Query MCP server directly for its description (if running)
     - Try HTTP GET to `http://10.0.0.2:{PORT}/health` or similar
   - **Option C:** Fallback to generic description based on server name
     - e.g., "tkn-cloudflare" → "Cloudflare infrastructure management"

4. **Read current configuration** - Read `~/.claude-profile/mcp-servers.json`

5. **Identify gaps** - Compare deployed servers against configured servers
   - Missing: In compose.yaml but not in mcp-servers.json
   - Orphaned: In mcp-servers.json but not in compose.yaml (report only, don't remove)

6. **Add missing servers** - For each missing server:
   - name: From compose.yaml comment
   - transport: "sse"
   - url: "http://10.0.0.2:{PORT}/sse"
   - description: From discovery (step 3)

7. **Report results** - Show what was added, including port numbers and sources used

## Important Changes

**Previous behavior (WRONG):**
- Assumed port numbers in compose.yaml matched README table
- Used README port numbers

**Current behavior (CORRECT):**
- Parse actual port mappings from compose.yaml lines: `- "XXXX:YYYY"  # server-name`
- Use left-side port (XXXX) as the actual deployed port
- Match descriptions by server NAME, not port number
- Handle servers not yet in README (use generic description)

## Format for New Entries

```json
{
  "name": "tkn-{service}",
  "transport": "sse",
  "url": "http://10.0.0.2:{PORT}/sse",
  "description": "{Description from README table}"
}
```

## Implementation Guidance

### Step 1: Find Compose File

```bash
# Find TKN MCP server compose files
Glob "**/compose.yaml" ~/git-bnx/TKN/

# Expected paths:
# ~/git-bnx/TKN/TKNet-MCPServer/compose.yaml
# ~/git-bnx/TKN/TKNet-Docker-Stacks/mcp-servers/compose.yaml
```

### Step 2: Parse Port Mappings

Use Grep with regex to extract port mappings:

```bash
# Find uncommented port lines with server names
Grep '^\s*- "[0-9]+:[0-9]+"\s*#\s*' compose.yaml -n

# Parse format: - "8200:8200"  # tkn-cloudflare
# Extract: port=8200, name=tkn-cloudflare
```

**Parsing logic:**
- Match: `- "(\d+):(\d+)"\s*#\s*(.+)$`
- Use left port number (first capture group)
- Extract server name from comment (third capture group, trimmed)
- Skip any line starting with `#` (commented out)

### Step 3: Get Descriptions

**Priority order:**

1. **README table** (most reliable)
   ```bash
   Grep "^\|.*\|.*\|.*\|$" ~/git-bnx/TKN/TKNet-MCPServer/README.md
   # Parse markdown table, match by server name
   ```

2. **Fallback descriptions** (if README doesn't have entry)
   - Parse server name: `tkn-{service}` → `{service} management`
   - Example: `tkn-cloudflare` → "Cloudflare management"
   - Example: `bnx-googleworkspace` → "Google Workspace management (BoroughNexus)"

### Step 4: Validation

Before adding, verify:
- Port is in range 8000-9000
- Server name follows pattern: `(tkn|bnx)-{service}`
- No duplicate names in mcp-servers.json
- Port mapping is valid: `"XXXX:XXXX"` (matching ports for SSE)

## Important Notes

- **Dynamic discovery**: Don't hardcode line numbers or file paths
- **Actual ports**: Use left-side port from `"PORT:PORT"` mapping, not README
- **Name matching**: Match descriptions by server NAME, not port number
- **Graceful degradation**: If README is outdated, use generic descriptions
- **Skip commented**: Only process uncommented lines in compose.yaml
- **Host IP**: Always `10.0.0.2` for TKN homelab
- **Transport**: Always `sse` for docker-deployed MCP servers

## Example

If compose.yaml shows:
```yaml
ports:
  - "8211:8211"  # tkn-arr
```

And README shows:
```markdown
| tkn-arr | 8211 | Sonarr, Radarr, Prowlarr |
```

Then add to mcp-servers.json:
```json
{
  "name": "tkn-arr",
  "transport": "sse",
  "url": "http://10.0.0.2:8211/sse",
  "description": "Sonarr, Radarr, Prowlarr"
}
```
