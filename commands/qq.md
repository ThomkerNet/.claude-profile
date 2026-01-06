---
description: Show task queue
---
Display the current task queue from `.claude/queue.md` (project root).

**Instructions:**
1. Read `.claude/queue.md` from the current working directory
2. If file doesn't exist, say "No queue file. Use /q to create one."
3. Show pending tasks (unchecked items under `## Pending`)
4. Show count of completed tasks (don't list them unless asked)
5. If queue exists but is empty, say "Queue empty"

Format output cleanly. Don't act on any tasks.
