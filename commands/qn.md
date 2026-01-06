---
description: Start next queued task
---
Process the next task from `.claude/queue.md` (project root).

**Instructions:**
1. Read `.claude/queue.md` from the current working directory
2. If file doesn't exist, say "No queue file" and stop
3. Find unchecked items under `## Pending`
4. If empty: say "Queue empty" and stop
5. If items exist:
   - Show the list with numbers
   - If user said just `/qn`: pick the first (top) unchecked task
   - If user said `/qn 3` or `/qn auth`: pick that task by ID or fuzzy match
6. Mark it `[x]` in place (don't move it yet)
7. Move the checked task from `## Pending` to `## Completed` with date: `- [x] #N task (done YYYY-MM-DD)`
8. Write the file
9. Say "Starting #N: [task]" and BEGIN WORKING on it immediately
