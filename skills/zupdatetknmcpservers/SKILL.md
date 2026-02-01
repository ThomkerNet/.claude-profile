---
name: zupdatetknmcpservers
description: Sync MCP servers from TKNet-MCPServer repo to claude-profile mcp-servers.json
---

# Sync TKN MCP Servers to Claude Profile

Ensure all deployed MCP servers from `~/git-bnx/TKN/TKNet-MCPServer` are configured in this Claude profile's `mcp-servers.json`.

## Task

1. **Read source of truth** - Read `~/git-bnx/TKN/TKNet-MCPServer/README.md` to get the table of available servers (lines 44-66)

2. **Read current configuration** - Read `~/.claude-profile/mcp-servers.json` to see what's currently configured

3. **Read deployment configuration** - Read `~/git-bnx/TKN/TKNet-MCPServer/compose.yaml` ports section (lines 71-80) to identify which servers are actually deployed/exposed

4. **Identify missing servers** - Compare the deployed servers (from compose.yaml ports) against mcp-servers.json and identify any that are missing

5. **Add missing servers** - For each missing server, add an entry to mcp-servers.json with:
   - name: Server name from README table (e.g., "tkn-cloudflare")
   - transport: "sse"
   - url: "http://10.0.0.2:{PORT}/sse" where PORT comes from compose.yaml
   - description: Description from README table

6. **Preserve existing entries** - Don't modify existing entries, only add missing ones

7. **Report results** - Show what was added (if anything)

## Format for New Entries

```json
{
  "name": "tkn-{service}",
  "transport": "sse",
  "url": "http://10.0.0.2:{PORT}/sse",
  "description": "{Description from README table}"
}
```

## Important Notes

- Only add servers that are **deployed** (have ports exposed in compose.yaml)
- Use port numbers from compose.yaml (e.g., 8200, 8201, etc.)
- Descriptions should match the README table exactly
- The host is always `10.0.0.2` (homelab server)
- Transport is always `sse` for TKN servers
- Don't add commented-out ports from compose.yaml (those are not deployed yet)

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
