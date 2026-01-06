---
description: Queue a task for later (deferred work)
---
Add a task to the project's queue file `.claude/queue.md` (in project root, not home).

**Task to queue:** $ARGUMENTS

**Instructions:**
1. Look for `.claude/queue.md` in the current working directory (project root)
2. If it doesn't exist, create it with this template:
   ```markdown
   # Task Queue

   ## Pending

   ## Completed
   ```
3. Find the highest existing task number (e.g., `#3`) in the Pending section, or start at `#1` if empty
4. Append under `## Pending`: `- [ ] #N $ARGUMENTS` (where N is next number)
5. If I'm currently working on something relevant, add a context line below:
   `  <!-- context: brief note about current files/state -->`
6. Write the file back
7. Respond briefly: "Queued #N: [task summary]"

Do NOT start working on this task. Just queue it.
