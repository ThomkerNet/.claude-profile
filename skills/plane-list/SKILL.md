---
name: plane-list
description: View issues in a Plane project, grouped by state. Defaults to open issues only; pass "all" to include Done/Cancelled. Pass a project identifier (MCP, TKN, CP, UNR, HA, HOST) to override the project.
---

# View Plane Issues

Show a readable overview of issues in a Plane project, grouped by state.

**Workspace slug:** `thomkernet`

## Arguments

`$ARGUMENTS` — Optional. Can be:
- A project identifier: `MCP`, `TKN`, `CP`, `UNR`, `HA`, `HOST`, `SETUP`, `INBOX`
- The word `all` to include Done/Cancelled issues
- Both, in any order: e.g. `TKN all` or `all MCP`

If no project is specified, auto-select from current working directory.

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

### Step 1: Parse arguments

From `$ARGUMENTS`:
- Extract project identifier (if present)
- Check if `all` appears — if so, set `show_all = true`
- If no project identifier found, auto-select from current working directory

### Step 2: Fetch states and issues in parallel

Call **both** of these simultaneously:
- `list_states` for the project → build a map of `state_id → state_group` (`backlog`, `unstarted`, `started`, `completed`, `cancelled`) and `state_id → state_name`
- `list_issues` for the project with **no state_group filter** (the API ignores the filter anyway and returns all issues)

**Important:** The `list_issues` state_group parameter does not work reliably — it returns all issues regardless. Always fetch all and filter client-side using the states map from `list_states`.

### Step 3: Filter issues

Using the `state_id → state_group` map:

- **Default mode** (`show_all = false`): keep only issues where `state_group` is `backlog`, `unstarted`, or `started`. Exclude `completed` and `cancelled`.
- **All mode** (`show_all = true`): keep all issues.

### Step 4: Group and sort

Group filtered issues by state_group in this order:
1. `started` → "IN PROGRESS" (▶)
2. `unstarted` → "TODO" (📋)
3. `backlog` → "BACKLOG" (📦)
4. `completed` → "DONE" (✅) — only in `all` mode
5. `cancelled` → "CANCELLED" (🚫) — only in `all` mode

Within each group, sort by priority: urgent → high → medium → low/none, then by sequence_id descending.

### Step 5: Display

Priority indicators: `🔴` urgent, `🟠` high, `🟡` medium, `⚪` low/none

```
══════════════════════════════════════════════
  TKNet MCP Servers (MCP)  —  14 open issues
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

If backlog has more than 5 items, show the top 5 by priority and note how many more exist.

In `all` mode, also show DONE and CANCELLED sections, but cap each at 10 most recent (by sequence_id descending) to avoid noise.

### Step 6: Summary line

After the list, print:
- Total open issues (backlog + todo + in progress) — or total all issues if `show_all`
- How many are urgent/high priority
- If any issues are assigned to you (`simon`, member `0d6f8108-c668-471d-a6ff-b0fa5af9bcfc`), highlight them
- If `show_all = false`, note: `Show completed: /plane-list TKN all`
