---
name: plane-claim
description: Claim a Plane issue — assigns it to simon and transitions it to In Progress. Pass the issue identifier like MCP-18 or TKN-5.
---

# Claim a Plane Issue

Atomically assign an issue to `simon` and transition it to **In Progress**.

**Workspace slug:** `thomkernet`

## Arguments

`$ARGUMENTS` — Required. Issue identifier in `PROJECT-N` format, e.g. `MCP-18`, `TKN-5`, `CP-3`.

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

### Step 1: Parse the identifier

From `$ARGUMENTS`, extract:
- `project_prefix` = everything before the `-` (e.g., `MCP`)
- `sequence_id` = the number after the `-` (e.g., `18`)

Look up `project_id` from the mapping above. If the prefix is unrecognised, report the error and stop.

### Step 2: Find the issue UUID

Call `list_issues` with `workspace_slug: "thomkernet"` and the resolved `project_id`. Iterate results to find the issue where `sequence_id` matches. Extract its UUID (`id` field).

If not found: report `Issue MCP-18 not found in project TKNet MCP Servers` and stop.

### Step 3: Call claim_issue

```
claim_issue(
  workspace_slug="thomkernet",
  project_id="<UUID>",
  issue_id="<issue UUID>"
)
```

The tool atomically:
1. Assigns the issue to the current user (`simon`)
2. Transitions state to **In Progress** (`started`)
3. Posts an activity comment

### Step 4: Confirm

```
Issue claimed:
  ID:       MCP-18
  Title:    Add HITL approval flow for delete_issue
  Project:  TKNet MCP Servers
  State:    → In Progress
  Assigned: simon
  URL:      http://100.74.34.7:8300/thomkernet/projects/MCP/issues/18/

Mark it done when finished: /plane-done MCP-18 <summary>
```

## Error Handling

- If `$ARGUMENTS` is empty: print usage — `Usage: /plane-claim MCP-18`
- If issue is already assigned / in progress: report the current state and assignee; do not re-claim
- If issue is in `completed` or `cancelled` state: warn and ask user to confirm before proceeding
