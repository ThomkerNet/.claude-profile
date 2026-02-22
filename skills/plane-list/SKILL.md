---
name: plane-list
description: View active issues in a Plane project. Defaults to the project relevant to current working directory. Pass a project identifier (MCP, TKN, CP, UNR, HA, HOST) to override.
---

# View Plane Issues

Show a readable overview of issues in a Plane project, grouped by state.

**Workspace slug:** `thomkernet`

## Arguments

`$ARGUMENTS` — Optional project identifier: `MCP`, `TKN`, `CP`, `UNR`, `HA`, `HOST`, `SETUP`, `INBOX`. If empty, select based on current working directory.

## Project Mapping

| Identifier | Project Name | ID |
|---|---|---|
| MCP | TKNet MCP Servers | `8efae843-0c06-4ba8-b8f4-04461e6c8922` |
| TKN | TKN Homelab | `1974b497-eb64-41b4-b927-8fcb80114bc6` |
| CP | TKNet Claude Profile | `2b0c78e5-7304-447f-8d1f-c6e4fb97bcd4` |
| UNR | TKNet Unraid | `3027e0bf-f83d-4c58-a74d-b0f535c530de` |
| HA | TKNet Home Assistant | `d6e19072-bee5-4b3a-aedb-97e6b3141c8e` |
| HOST | TKNet Hosting | `82b58c20-dbd4-4607-991a-36e979066404` |
| SETUP | TKNet Ubuntu Claude Setup Script | `9ffdc926-5c41-4964-b381-5cf72a7fb9a5` |
| INBOX | Inbox | `0dd1bf14-2969-4c14-8e70-e4c4531cf137` |

**Auto-select by directory:**
- `TKNet-MCPServer/` → MCP
- `TKNet-Docker-Stacks/` → TKN
- `TKNet-Claude-Profile/` → CP
- Other → TKN

## Workflow

### Step 1: Determine project

Parse `$ARGUMENTS` as the project identifier. If empty, select from current working directory using the mapping above.

### Step 2: Fetch issues

Call `list_issues` for the selected project (no state filter — get all). You may need to call it multiple times with different `state_group` values if needed: `backlog`, `unstarted`, `started`, `completed`, `cancelled`.

Fetch `backlog`, `unstarted`, and `started` issues. Skip `completed` and `cancelled` unless the list is sparse (fewer than 5 total active issues), in which case also show the 5 most recently completed.

### Step 3: Display

Print a clean, scannable list grouped by state. Use priority indicators:

Priority indicators: `🔴` urgent, `🟠` high, `🟡` medium, `⚪` low/none

```
══════════════════════════════════════════════
  TKNet MCP Servers (MCP)  —  14 active issues
══════════════════════════════════════════════

▶ IN PROGRESS (2)
  MCP-18  🟠  Add HITL approval flow for delete_issue
  MCP-12  🟡  Investigate SSE reconnect drops under load

📋 TODO (3)
  MCP-20  🟠  Migrate authentik server to new image tag
  MCP-17  🟡  Add rate limiting to firecrawl proxy
  MCP-15  ⚪  Update CLAUDE.md with new transport URLs

📦 BACKLOG (9)
  MCP-21  🔴  [MCP Proxy] 404 on /mcp route after Mount refactor
  MCP-19  🟠  Google Workspace token refresh fails silently
  MCP-14  🟡  Add plane-list slash command
  MCP-11  🟡  Document env_prefix pattern in README
  MCP-9   ⚪  Clean up orphaned Tailscale nodes
  ... (4 more)

──────────────────────────────────────────────
  Claim an issue: /plane-claim MCP-18
  Log a bug:      /plane-bug
  Log a task:     /plane-task
══════════════════════════════════════════════
```

If backlog has more than 5 items, show the top 5 by priority (urgent first, then high, then by sequence_id descending) and note how many more exist.

### Step 4: Summary line

After the list, print:
- Total active issues (backlog + todo + in progress)
- How many are urgent/high priority
- If any issues are assigned to you (`simon`, member `0d6f8108-c668-471d-a6ff-b0fa5af9bcfc`), highlight them
