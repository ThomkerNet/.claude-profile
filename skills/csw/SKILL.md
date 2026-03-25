---
name: csw
description: Context switch — find and activate the most appropriate session context for a given task description
---

# Context Switch (`/csw`)

> Load the best session context for the work you're about to do.

## Usage

```
/csw describe what you want to work on
/csw swarmops dispatch routing
/csw bnx auth flow refactor
/csw                          # auto-detect from cwd + git remote
```

## What It Does

Finds and activates the most relevant session context from the `tkn-context` MCP server, then injects it into the current session so you have the right reference material and startup instructions ready.

## Execution Steps

### Step 1: Gather signals

Collect location signals to feed into resolution:

```bash
# Current working directory
pwd

# Git remote (if in a repo)
git remote get-url origin 2>/dev/null || echo ""
```

### Step 2: Try auto-resolution first

Call `context_resolve` with the cwd and git remote from Step 1. This uses registered `path_prefix` and `git_remote` mappings for an exact match.

### Step 3: Search by description

If `$ARGUMENTS` is non-empty, call `context_list` with `query: "$ARGUMENTS"` to find contexts matching the description. Limit to 5 results.

### Step 4: Pick the best match

Scoring priority (highest wins):
1. **Auto-resolve hit AND description match** — same context appears in both → definite winner
2. **Auto-resolve hit only** — cwd/git-remote mapped context, even if description vague
3. **Description match** — best text match from `context_list` results
4. **No match** — report "no context found" and list all available contexts via `context_list`

If multiple candidates remain tied, prefer the one whose `name` or `description` most closely matches `$ARGUMENTS`.

### Step 5: Activate

Call `context_activate` with the winning context's name or ID. Output the full result — this IS the context injection.

### Step 6: Report

After activating, briefly note:
- Which context was loaded and why (auto-resolved / description match / both)
- Any close runner-up alternatives (if score was close), so the user can switch with `/csw <name>`

## Quick switch by name

If `$ARGUMENTS` is a single word that exactly matches a context name, skip Steps 1-4 and jump straight to `context_activate`.

## No context found

If nothing matches, call `context_list` with no filter and display all available contexts as a table:

| Name | Description | Tags |
|------|-------------|------|

Then ask: "Which would you like to load?"

## Notes

- Run Steps 1-3 in parallel where possible
- `context_activate` output is the context itself — display it in full, don't summarize it
- If the activated context has **Startup Instructions**, execute them immediately after displaying
