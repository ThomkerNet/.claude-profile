---
name: csw
description: Context switch — find and activate the most appropriate session context for a given task description
---

# Context Switch (`/csw`)

> Load the best session context for the work you're about to do.

## Usage

```
/csw swarmops dispatch routing      # search by description
/csw bnx auth flow refactor         # search by description
/csw @swarmops                      # activate by exact name (use @ prefix)
/csw                                # auto-detect from cwd + git remote
```

## What It Does

Finds and activates the most relevant session context from the `tkn-context` MCP server, injecting reference material and startup instructions for the work you're about to do.

## Execution Steps

### Step 0: Exact name fast-path

If `$ARGUMENTS` starts with `@`, strip the `@` and call `context_get(name_or_id)`:
- If found → jump directly to **Step 4: Activate**
- If not found → report error: "No context named `<name>` found" and call `context_list(limit=50)` to show all available, then stop

### Step 1: Gather signals (run all in parallel)

**1a — Location:**
```bash
pwd
git remote get-url origin 2>/dev/null || echo ""
```
Treat failed/missing git remote as empty string.

**1b — Auto-resolve:** Call `context_resolve(cwd=<pwd result>, git_remote=<remote or omit if empty>)`

**1c — Search:** If `$ARGUMENTS` is non-empty, call `context_list(query="$ARGUMENTS", limit=5)`. Skip if `$ARGUMENTS` is empty.

### Step 2: Build candidate set

Candidates are the union of:
- Auto-resolve result (if any)
- Results from `context_list` (if any)

Compare by `id` when available, otherwise normalized name (lowercase, trimmed).

### Step 3: Select winner

Apply this priority order — first rule that yields a clear winner wins:

1. **Agree** — auto-resolve context AND appears in `context_list` results → definite winner
2. **Intent** — `$ARGUMENTS` is non-empty → top result from `context_list` wins (explicit user intent outweighs location)
3. **Location** — `$ARGUMENTS` is empty → auto-resolve result wins (no description, trust cwd/remote)
4. **Fallback** — no `$ARGUMENTS` and auto-resolve failed → derive a query from the cwd basename or remote repo name (e.g. `path/to/swarmops` → query `swarmops`), call `context_list(query=<derived>, limit=5)`, pick top result
5. **Nothing found** → go to **No Context Found**

**Tie-breaking** (same priority tier, multiple candidates): exact normalized name match in `$ARGUMENTS` → earlier in `context_list` order → lexical sort by name.

### Step 4: Activate

Call `context_activate(name_or_id=<winner id or name>)`.

**Output the complete response verbatim** — do not summarize or truncate it. This is the context injection.

If `context_activate` fails (tool error, context deleted, server unavailable):
- Report the error clearly
- Fall back to `context_list(limit=50)` and show available contexts as a table
- Stop

### Step 5: Report

Before the activation output, print a single line:
```
Activated: **<context name>** (<reason: auto-resolved / description match / both / fallback>)
```
If there is a runner-up candidate in the same priority tier, add:
```
Alternative: `/csw @<runner-up name>` — <runner-up description>
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

Then say: "No matching context found. Which would you like to load? Reply with `/csw @<name>`."

## Notes

- Steps 1a, 1b, 1c all run in parallel
- `context_activate` output is the context — output it in full, verbatim
- If MCP tools are unavailable, report the error and exit cleanly; do not attempt to guess at context
