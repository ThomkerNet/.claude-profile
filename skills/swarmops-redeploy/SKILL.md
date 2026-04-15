---
name: swarmops-redeploy
description: Build, deploy, and restart the SwarmOps backend service and TUI on nuc-ubuntu-dev. Ensures the latest code is running. Use when SwarmOps needs to be updated, after code changes, or when "swarmops redeploy" is mentioned.
---

# SwarmOps Redeploy

Build the latest SwarmOps binary, restart the backend service, and verify it's running cleanly.

## When to Use

- "redeploy swarmops"
- After implementing fixes to the SwarmOps codebase
- "commit and push swarmops to the repo" (do this first, then redeploy)
- When pool sessions are stale or the backend is out of date

## Quick Command

```bash
swarmops redeploy
```

This is the canonical command — it pulls latest, builds, runs tests, restarts the service, and waits for the backend to be ready. Always use this rather than manual steps.

## What It Does

1. `git pull` — fetch latest from remote
2. `make build` (or `go build`) — compile the binary
3. Run tests
4. `systemctl restart swarmops` — restart the backend service
5. Wait for the backend to be healthy before returning

## Manual Steps (if `swarmops redeploy` fails)

SSH to `nuc-ubuntu-dev`:

```bash
cd ~/swarmops    # or wherever the repo is checked out
git pull
go build -o swarmops .
sudo systemctl restart swarmops
sudo systemctl status swarmops
```

Check logs if the service doesn't start:
```bash
journalctl -u swarmops -n 50 --no-pager
```

## Verifying the Deploy

After redeploy:
1. `systemctl status swarmops` → should be `active (running)`
2. Launch TUI: `swarmops` → check top bar shows correct version/time
3. Verify pool sessions are listed and active
4. Test that Icinga and Plane panels load

## Pool Sessions

Pool sessions (haiku/sonnet/opus) are **separate** from the backend service:
- Restarting the service does **not** kill pool sessions automatically
- If pool sessions are stuck or stale, they need to be killed and respawned from the TUI
- The backend manages pool session lifecycle — after a clean restart, it should respawn them

## Common Issues

| Symptom | Fix |
|---------|-----|
| `systemctl restart` times out | Check for hung processes: `ps aux \| grep swarmops`, kill if needed |
| TUI doesn't show top bar | Binary may be stale — check that `swarmops redeploy` rebuilt, not just restarted |
| Pool slots jump around after deploy | Sorting bug — check recent commits for session ordering logic |
| "service may not start" error | Wait 30s and check `systemctl status` — race condition on startup |

## Repo Location

The SwarmOps repo is typically at one of:
- `~/git-bnx/swarmops/`
- Check `which swarmops` to find the installed binary location
- Check `systemctl cat swarmops` for the service ExecStart path

## After Deploy

If this was after implementing Plane issues, mark them done:
```
/plane-done SWM-<N> <summary>
```
