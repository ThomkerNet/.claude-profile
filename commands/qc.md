---
description: Clear completed tasks from queue
---
Archive completed tasks from `.claude/queue.md` (project root).

**Instructions:**
1. Read `.claude/queue.md` from the current working directory
2. If file doesn't exist, say "No queue file" and stop
3. Count items under `## Completed`
4. If none: say "No completed tasks to clear"
5. If some:
   - Remove all items under `## Completed` (keep the heading)
   - Write the file
   - Say "Cleared N completed tasks"

This is non-destructive cleanup. Completed tasks are just removed from view.
