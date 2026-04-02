---
name: csw
description: Context switch — find and activate the most appropriate session context for a given task description
argument-hint: "[task description or =context-name] e.g. =arr-media-stack, =tkn-homelab-infra, =tknet-mcpserver, =briefbox, =bnx-admin"
---

# Context Switch (`/csw`)

> Load the best session context for the work you're about to do.

## Usage

```
/csw swarmops dispatch routing      # AI-ranked match by description
/csw bnx auth flow refactor         # AI-ranked match by description
/csw =swarmops                      # activate by exact name (use = prefix)
/csw                                # interactive picker (MCP Elicitation dropdown)
```

## What It Does

Finds and activates the most relevant session context from the `tkn-context` MCP server, injecting reference material and startup instructions for the work you're about to do.

## Execution Steps

### Step 0: Exact name fast-path

If `$ARGUMENTS` starts with `=`, strip the `=` and call `context_get(name_or_id)`:
- If found → jump directly to **Step 4: Activate**
- If not found → report error: "No context named `<name>` found" and call `context_list(limit=50)` to show all available, then stop

> **Note:** `@` is reserved by Claude Code for file/directory references. Use `=` for exact name lookups.

### Step 1: No arguments — interactive picker

If `$ARGUMENTS` is empty, call `context_pick()` (MCP Elicitation tool).

This presents a dropdown of all available contexts for the user to select from. The selected context is activated automatically by the tool.

**Output the complete `context_pick` response verbatim** — it includes the activated context content.

If `context_pick` fails (elicitation not supported, server error):
- Fall back to `context_list(limit=50)` and show available contexts as a table
- Say: "Interactive picker unavailable. Reply with `/csw =<name>` to load a context."
- Stop

After successful activation, go to **Step 5: Report** (reason: "interactive picker").

### Step 2: With arguments — AI-ranked search + user choice

If `$ARGUMENTS` is non-empty (and doesn't start with `=`):

**2a** — In parallel:
- Call `context_list(limit=50)` to fetch ALL available contexts (names + descriptions).
- Get location signals:
  ```bash
  pwd
  git remote get-url origin 2>/dev/null || echo ""
  ```
  Call `context_resolve(cwd=<pwd>, git_remote=<remote or omit if empty>)`.

**2b** — Call `mcp__tkn-aipeer__quick_consult` to rank contexts by relevance:

```
quick_consult(
  question: "Rank these session contexts by relevance to the task: \"$ARGUMENTS\". Return ONLY a JSON array of context names, most relevant first. Only include plausible matches. If nothing matches, return [].",
  context: "<for each context from 2a: one line per context: 'name — description'>",
  consultation_type: "general"
)
```

**2c** — Extract the JSON array from the response content. Parse into a ranked list.

### Step 3: Present ranked options for user choice

Display the AI-ranked contexts as a numbered list. Mark the auto-resolved context if it appears. Always include a "create new" option at the end.

```
Best matches for "claude profile skills config":

  1. claude-profile — Claude Code profile configuration, skills, commands, hooks...
  2. tknet-mcpserver — MCP server development and deployment... ← auto-resolved from cwd
  3. tkn-homelab-infra — TKN homelab infrastructure...

  N. Create new context for this task

Pick a number (or Enter for 1):
```

If the AI returned an empty array, show:
```
No strong matches for "claude profile skills config". Available contexts:

  1. <all contexts listed alphabetically>
  ...
  N. Create new context for this task

Pick a number:
```

Wait for user input via AskUserQuestion.

- If user picks a number → activate that context (Step 4)
- If user picks "create new" → ask for a context name, then call `context_create(name=<name>)` and report. Do NOT activate — the new context is empty. Say: "Context created. Populate it with content, then `/csw =<name>` to activate."

### Step 4: Activate

Call `context_activate(name_or_id=<winner name>)`.

**Output the complete response verbatim** — do not summarize or truncate it. This is the context injection.

If `context_activate` fails (tool error, context deleted, server unavailable):
- Report the error clearly
- Fall back to `context_list(limit=50)` and show available contexts as a table
- Stop

### Step 5: Report

Before the activation output, print a single line:
```
Activated: **<context name>** (<reason: interactive picker / AI-ranked match / exact name>)
```

### Step 6: Startup instructions

If the activated context includes a **Startup Instructions** / **Startup Actions** section:
- Display the instructions
- **Do not execute shell commands automatically**
- Ask: "Run startup instructions? (y/n)" before executing anything that changes state

Purely informational instructions (read-only `git status`, `pwd`, etc.) may run without confirmation.

## No Context Found

Call `context_list(limit=50)` and display results as:

| Name | Description | Tags |
|------|-------------|------|

Then say: "No matching context found. Which would you like to load? Reply with `/csw =<name>`."

## Notes

- `context_pick` requires MCP Elicitation support — if the client doesn't support it, the fallback shows a table
- Ranking uses `quick_consult` (external LLM via tkn-aipeer) to avoid system context bloat that prevents Haiku agents from working
- `context_activate` output is the context — output it in full, verbatim
- If MCP tools are unavailable, report the error and exit cleanly; do not attempt to guess at context
