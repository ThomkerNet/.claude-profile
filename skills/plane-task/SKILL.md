---
name: plane-task
description: Create a task or feature request in Plane. If no text is provided, infers the task from recent session context.
---

# Create a Task in Plane

Log a well-described task or feature request to the appropriate Plane project.

**Workspace slug:** `thomkernet`

## Arguments

`$ARGUMENTS` — Optional task description or title. If empty, infer the task from recent session context: what was being worked on, what goal was attempted, what improvement was identified.

## Project Selection

| Directory / Context | Project | ID |
|---|---|---|
| `TKNet-MCPServer/` or MCP server code | MCP | `8efae843-0c06-4ba8-b8f4-04461e6c8922` |
| `TKNet-Docker-Stacks/` or compose/deployment | TKN | `1974b497-eb64-41b4-b927-8fcb80114bc6` |
| `TKNet-Claude-Profile/` or claude profile | CP | `2b0c78e5-7304-447f-8d1f-c6e4fb97bcd4` |
| Unraid OS / array / disk | UNR | `3027e0bf-f83d-4c58-a74d-b0f535c530de` |
| Home Assistant | HA | `d6e19072-bee5-4b3a-aedb-97e6b3141c8e` |
| General homelab / infra (default) | TKN | `1974b497-eb64-41b4-b927-8fcb80114bc6` |

## Workflow

### Step 1: Draft the task

**Title:** Clear, action-verb opener — `Add X`, `Implement Y`, `Migrate Z to W`, `Investigate why X`

**Description (HTML):**

```html
<h2>Goal</h2>
<p>What needs to be done and why. Include the motivation or problem this solves.</p>

<h2>Scope</h2>
<ul>
  <li>In scope: ...</li>
  <li>Out of scope (if relevant): ...</li>
</ul>

<h2>Acceptance Criteria</h2>
<ul>
  <li>[ ] Criterion 1</li>
  <li>[ ] Criterion 2</li>
</ul>

<h2>Implementation Notes</h2>
<p>Key files, patterns, or approaches to consider. Omit if nothing specific to note.</p>
<ul>
  <li>Relevant file: <code>path/to/file.py</code></li>
  <li>Pattern to follow: ...</li>
</ul>

<h2>References</h2>
<ul>
  <li>Related issue or context: ...</li>
</ul>
```

Skip sections that are not applicable. For simple/obvious tasks, a `<h2>Goal</h2>` + `<h2>Acceptance Criteria</h2>` is sufficient.

### Step 2: Determine priority

- `urgent` — Blocks a release or critical deployment
- `high` — Important, needed soon
- `medium` — Standard backlog work (default)
- `low` — Nice to have

### Step 3: Labels (MCP project only)

If the project is `MCP`:
- Feature/enhancement: `labels: ["37dec6a5-b22f-4257-8ac1-dbb2e39a5928"]`
- Bug fix: `labels: ["c9efd84e-fb3e-44f3-88dd-6a61b65f1c3a"]`

### Step 4: Create the issue

Call `create_issue` with:
- `workspace_slug`: `thomkernet`
- `project_id`: (from project mapping)
- `name`: (title)
- `state_group`: `backlog`
- `priority`: (determined above)
- `description_html`: (full HTML)
- `labels`: (MCP only, if applicable)

### Step 5: Confirm

```
Task created in Plane:
  ID:       TKN-15
  Title:    Add Tailscale exit node configuration
  Project:  TKN Homelab (TKN)
  Priority: medium
  State:    Backlog
  URL:      http://100.74.34.7:8300/thomkernet/projects/TKN/issues/15/
```
