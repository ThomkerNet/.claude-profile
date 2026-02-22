---
name: plane-done
description: Mark a Plane issue as Done. Pass the issue identifier and an optional completion summary. Example: /plane-done MCP-18 Fixed the 404 by switching from Mount to Route.
---

# Mark a Plane Issue as Done

Transition an issue to **Done** and optionally post a completion summary comment.

**Workspace slug:** `thomkernet`

## Arguments

`$ARGUMENTS` — Required. Format: `PROJECT-N [optional summary text]`

Examples:
- `/plane-done MCP-18`
- `/plane-done TKN-5 Migrated stack to standalone pattern, deployed via Komodo`

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

## Workflow

### Step 1: Parse arguments

Split `$ARGUMENTS` on the first space:
- `issue_ref` = first token (e.g., `MCP-18`)
- `summary` = remainder (e.g., `Fixed the 404 by switching from Mount to Route`) — may be empty

Extract `project_prefix` and `sequence_id` from `issue_ref`.

### Step 2: Find the issue UUID

Call `list_issues` with `workspace_slug: "thomkernet"` and the resolved `project_id`. Find the issue matching the `sequence_id`. Extract its UUID.

If not found: report `Issue MCP-18 not found` and stop.

### Step 3: Build the completion comment

If `summary` was provided, use it.

If `summary` is empty, synthesise a brief completion note from recent session context — what was done, any key decisions made. Keep it to 2-4 sentences.

Format as HTML:
```html
<p>✅ <strong>Completed.</strong> {summary}</p>
<p>Closed via /plane-done from Claude Code session.</p>
```

### Step 4: Call complete_issue

```
complete_issue(
  workspace_slug="thomkernet",
  project_id="<UUID>",
  issue_id="<issue UUID>",
  comment_html="<HTML from Step 3>"
)
```

The tool validates the issue is in a started state (or allows override) and transitions it to `completed`.

### Step 5: Confirm

```
Issue marked as done:
  ID:       MCP-18
  Title:    Add HITL approval flow for delete_issue
  Project:  TKNet MCP Servers
  State:    → Done ✅
  Comment:  "Fixed the 404 by switching from Mount to Route."
  URL:      http://100.74.34.7:8300/thomkernet/projects/MCP/issues/18/
```

## Error Handling

- If `$ARGUMENTS` is empty: print usage — `Usage: /plane-done MCP-18 [optional summary]`
- If issue is already `completed`: report that it's already done; show existing completion time
- If issue is in `backlog` or `unstarted` (never started): warn the user — suggest `/plane-claim MCP-18` first, or ask if they want to close it anyway
- If issue is `cancelled`: report state; ask for confirmation before changing to done
