---
name: fabric
description: Enhance a prompt using the Fabric pattern library. Finds the best expert pattern for an intent and returns a structured dispatch pack ready for Claude Code, SwarmOps, or any agent.
---

# Fabric Prompt Enhancement

Use the `tkn-fabric` MCP server to find the best Fabric pattern for the user's intent and return a richly-structured expert framing.

## Arguments

`$ARGUMENTS` — The intent or task to enhance. If empty, ask the user what they want to do.

## Workflow

### Step 1: Enhance the prompt

Call `mcp__tkn-fabric__enhance_prompt` with:
- `intent`: `$ARGUMENTS` (or ask user)
- `injection_mode`: `"both"` (default — returns system_prompt + enhanced_task + formatted_description)

### Step 2: Present the result

Show the user:

```
Pattern matched:  <pattern_name> (<confidence_pct>% confidence)
Selection method: <method>
<if degraded>⚠ Degraded: LLM reranking unavailable, using TF-IDF only</if>
<if low_confidence>⚠ Low confidence — this may not be the best pattern</if>

## Expert Framing (System Prompt)
<system_prompt — first 500 chars, then "... [truncated]">

## Enhanced Task
<enhanced_task>

---
Formatted dispatch pack ready for injection.
```

### Step 3: Ask what to do next

```
What would you like to do?
  1. Use this as-is (copy the dispatch pack)
  2. Create a SwarmOps task with this brief
  3. Try a different pattern
  4. Refine the intent
```

### Step 4: Handle each path

**Option 1 — Use as-is:**
Output the `formatted_description` from the envelope. Done.

**Option 2 — Create SwarmOps task:**
Ask for:
- `session_id` — SwarmOps session ID (required)
- `title` — short imperative title for the task (suggest one based on the intent)
- `stage` — default `queued`
- `goal_id` — optional

Then call `mcp__tkn-fabric__create_swarmops_task` with `fabric_enhance=False` (already enhanced above, pass `description=formatted_description`).

Confirm: "Task created in SwarmOps session `<session_id>` — ID: `<task_id>`"

**Option 3 — Try a different pattern:**
Call `mcp__tkn-fabric__select_pattern` with `intent=$ARGUMENTS, top_k=5`.
Show the top 5 matches with score and identity_excerpt.
Ask user to pick one (1-5).
Then call `mcp__tkn-fabric__get_pattern` with the selected pattern name to get the full system.md.
Display the system.md and ask if they want to use it.

**Option 4 — Refine the intent:**
Ask the user to rephrase their intent, then restart from Step 1.

## Error Handling

- If `fabric_health_check` shows `circuit_open: true` → warn the user: "Pattern refresh circuit breaker is open — patterns may be stale. An admin can reset it via `update_patterns`."
- If `pattern_count` is 0 → warn: "No patterns loaded. The server may need `update_patterns` to be run first (requires HITL approval)."
- If `confidence` < 0.40 → note it's low confidence but still show the result.
- If `degraded: true` → note that LLM reranking was unavailable and TF-IDF was used alone.
