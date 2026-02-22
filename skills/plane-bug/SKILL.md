---
name: plane-bug
description: Log a detailed bug report to Plane. If no text is provided, infers the bug from recent console errors and session context.
---

# Log a Bug to Plane

Log a verbose, AI-agent-ready bug report to the appropriate Plane project.

**Workspace slug:** `thomkernet`

## Arguments

`$ARGUMENTS` — Optional bug description or title. If empty, synthesize from recent session context: error messages, failed commands, stack traces, unexpected output.

## Project Selection

Map current working directory (or context) to project:

| Directory / Context | Project | ID |
|---|---|---|
| `TKNet-MCPServer/` or MCP server code | MCP | `8efae843-0c06-4ba8-b8f4-04461e6c8922` |
| `TKNet-Docker-Stacks/` or compose/deployment | TKN | `1974b497-eb64-41b4-b927-8fcb80114bc6` |
| `TKNet-Claude-Profile/` or claude profile | CP | `2b0c78e5-7304-447f-8d1f-c6e4fb97bcd4` |
| Unraid OS / array / disk | UNR | `3027e0bf-f83d-4c58-a74d-b0f535c530de` |
| Home Assistant | HA | `d6e19072-bee5-4b3a-aedb-97e6b3141c8e` |
| General homelab / infra (default) | TKN | `1974b497-eb64-41b4-b927-8fcb80114bc6` |

If ambiguous, use `TKN`.

## Workflow

### Step 1: Collect all relevant context

Look through the full conversation for:
- Error messages, stack traces, exception text
- Commands that were run and their output
- Files that were modified or read
- The goal that was being attempted
- What was tried and what failed

If `$ARGUMENTS` is provided, treat it as the primary description and supplement with context.

### Step 2: Draft a verbose, AI-agent-ready bug report

The report must be detailed enough for a new AI agent to begin fixing in a fresh session with no prior context.

**Title:** Concise, action-oriented — `[Component] Describe what is broken`

**Description (HTML)** — Populate ALL sections. Use `<h2>`, `<p>`, `<ul>`, `<ol>`, `<pre>`, `<code>` tags:

```html
<h2>Summary</h2>
<p>1-2 sentence description of what is broken and what impact it has.</p>

<h2>Environment</h2>
<ul>
  <li>Stack / Service: <code>service-name</code></li>
  <li>Working Directory: <code>/path/to/dir</code></li>
  <li>Relevant Files: <code>path/to/file.py:42</code>, <code>docker-compose.yml</code></li>
  <li>Image / Version: <code>registry/image:tag</code> (if known)</li>
  <li>Date: YYYY-MM-DD</li>
</ul>

<h2>Steps to Reproduce</h2>
<ol>
  <li>Step 1: ...</li>
  <li>Step 2: ...</li>
  <li>Step 3: observe the error</li>
</ol>

<h2>Expected Behavior</h2>
<p>What should happen when the steps above are followed.</p>

<h2>Actual Behavior</h2>
<p>What actually happens. Include the full, untruncated error output below.</p>
<pre><code>PASTE FULL ERROR / STACK TRACE / LOG OUTPUT HERE</code></pre>

<h2>Investigation So Far</h2>
<p>What was already tried, hypotheses that were ruled out, relevant findings.</p>
<ul>
  <li>Tried X → result was Y</li>
  <li>Checked Z → no issues found there</li>
</ul>

<h2>Suggested Debugging Approach</h2>
<ul>
  <li>Start by checking <code>file.py:42</code> — the error originates here</li>
  <li>Review the <code>SOME_ENV_VAR</code> environment variable</li>
  <li>Compare against working version at commit <code>abc1234</code></li>
</ul>

<h2>Key References</h2>
<ul>
  <li>File: <code>/abs/path/to/relevant/file.py</code></li>
  <li>Commit: <code>git-hash</code> (if relevant)</li>
  <li>Related issue: (if known)</li>
</ul>
```

Skip a section only if it is genuinely not applicable.

### Step 3: Determine priority

- `urgent` — System down, data loss risk, all work blocked
- `high` — Key feature broken, specific work blocked
- `medium` — Broken feature with a workaround (default)
- `low` — Minor issue, cosmetic, rarely hit

### Step 4: Labels (MCP project only)

If the project is `MCP`:
- Bug issues: `labels: ["c9efd84e-fb3e-44f3-88dd-6a61b65f1c3a"]`
- Enhancement issues: `labels: ["37dec6a5-b22f-4257-8ac1-dbb2e39a5928"]`

All other projects have no labels — omit the `labels` field.

### Step 5: Create the issue

Call `create_issue` with:
- `workspace_slug`: `thomkernet`
- `project_id`: (from Step 1 mapping)
- `name`: (title)
- `state_group`: `backlog`
- `priority`: (from Step 3)
- `description_html`: (full HTML from Step 2)
- `labels`: (from Step 4, only if MCP project)

### Step 6: Confirm

Print a confirmation block:
```
Bug logged to Plane:
  ID:       MCP-21
  Title:    [MCP Proxy] Streamable-http returns 404 on /mcp route
  Project:  TKNet MCP Servers (MCP)
  Priority: high
  State:    Backlog
  URL:      http://100.74.34.7:8300/thomkernet/projects/MCP/issues/21/
```
