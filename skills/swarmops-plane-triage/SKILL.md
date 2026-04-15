---
name: swarmops-plane-triage
description: Review and address all open SwarmOps Plane issues in a systematic cycle. Fetches issues from the SWM project, prioritises them, and works through them with iteratecycle. Use when Simon says "review swarmops plane issues", "address plane issues", or when starting a SwarmOps development session.
---

# SwarmOps Plane Issue Triage

Review open SwarmOps (RC Swarm / SWM) Plane issues and address them systematically.

## When to Use

- "review all recently submitted swarmops plane issues and address them"
- "check swarmops plane and fix what you can"
- Starting a SwarmOps development session
- After a SwarmOps deployment, to pick up new user-filed issues

## Workflow

### Step 1: Load issues

```
/plane-list SWM
```

Or call `list_issues` directly for project ID `d0f05492-f25d-4627-ad12-c6be3679e057` (workspace: `thomkernet`).

### Step 2: Prioritise

Group into:
1. **Bugs / regressions** — anything causing broken behaviour in the TUI or backend
2. **High-priority features** — marked urgent/high, or recently filed by Simon
3. **Low-priority / nice-to-haves** — backlog items

Skip issues already In Progress unless you're resuming them.

### Step 3: Work the list

For each issue in priority order:

1. **Claim it** → `/plane-claim SWM-<N>`
2. **Understand the issue** — read the description and any comments
3. **Navigate to the SwarmOps repo**:
   - Backend + TUI: `~/git-bnx/swarmops/` (or wherever the binary is built)
   - Check `git log --oneline -10` for recent context
4. **Implement the fix** → `/iteratecycle`
5. **Mark done** → `/plane-done SWM-<N> <summary>`

### Step 4: Deploy and verify

After working through issues:

```bash
# Build and restart the SwarmOps service
swarmops redeploy    # or: /swarmops-redeploy
```

Confirm the TUI loads cleanly and the fixed behaviour works.

## Key Context

- **SwarmOps repo**: check `~/git-bnx/swarmops/` or `~/git-bnx/TKN/` — look for `main.go`
- **Service name**: `swarmops` (systemctl on nuc-ubuntu-dev)
- **TUI launch**: `swarmops` or `swarmops tui`
- **Plane project**: SWM (`d0f05492-f25d-4627-ad12-c6be3679e057`)
- **Workspace**: `thomkernet`

## Pitfalls

- The Plane project slug may be `SWM` or `remote-code` — check with `/plane-list SWM`
- After a binary change, `swarmops redeploy` must complete before testing — don't just restart the TUI
- Pool sessions (haiku/sonnet/opus slots in the TUI) are separate from the backend — restart the service, not just the TUI
- The TUI top bar and session ordering have been fixed previously — if they regress, check recent commits for the relevant rendering code
