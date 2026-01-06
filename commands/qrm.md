---
description: Remove a task from queue
---
Remove a task from `.claude/queue.md` (project root) without completing it.

**Argument:** $ARGUMENTS (task ID like `3` or `#3`, or text to fuzzy match)

**Instructions:**
1. Read `.claude/queue.md` from the current working directory
2. If file doesn't exist, say "No queue file" and stop
3. Find the task in `## Pending` by:
   - Exact ID match: `#3` or just `3`
   - Or fuzzy text match if no ID given
4. If not found: say "No matching task found"
5. If found: remove the line (and any context comment below it)
6. Write the file
7. Confirm: "Removed #N: [task]"

Do NOT renumber remaining tasks (IDs are permanent).
