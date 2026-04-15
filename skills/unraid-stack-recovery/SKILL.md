---
name: unraid-stack-recovery
description: Recover Docker stacks on Unraid after a reboot or unexpected shutdown. Finds stopped containers, restarts them, and sets auto-start. Also handles accidental reboots, stopped MCP servers, and stack health checks. Use when Unraid has rebooted or when containers/stacks are reported as stopped.
---

# Unraid Stack Recovery

Recover Docker containers and stacks after an Unraid reboot or unexpected shutdown.

## When to Use

- "i accidentally rebooted the unraid server"
- "containers are down on Unraid"
- MCP servers are unreachable after a server restart
- "fix the stacks that are stopped and make them auto start"

## Workflow

### Step 1: Connect to Unraid

Use the `mcp__tkn-unraid__*` tools (preferred) or SSH profile `unraid` / `nas`.

```
get_docker_overview()    # quick health summary
list_containers()        # see all containers and their status
```

Or via SSH:
```bash
docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep -v "Up "
```

### Step 2: Identify stopped containers

Focus on:
- Containers with status `Exited` or `Created`
- MCP server containers (names starting with `mcp-`)
- Media stack containers (Sonarr, Radarr, Plex, Jellyfin, Prowlarr, Bazarr)
- Skip `init` containers (status `Exited (0)` — these are one-shot init tasks, not errors)

### Step 3: Restart stopped containers

```
restart_container(container_name="<name>")
```

Or via SSH:
```bash
docker start <container_name>
```

Restart in priority order:
1. Infrastructure (databases, reverse proxies, auth)
2. MCP servers (needed for Claude tools to work)
3. Media stack
4. Everything else

### Step 4: Verify health

After restarting:
```
get_docker_overview()
list_containers()
```

Check for containers that started but immediately stopped again — these need investigation (`get_container_logs`).

### Step 5: Set auto-start (if needed)

If containers were not set to auto-start:
- In Unraid UI: Docker tab → container settings → "Autostart: Yes"
- Note: Most stacks should already auto-start — if they didn't, check if the Docker service started before the containers were ready

### Step 6: Check MCP health

After recovery, verify key MCP servers are responsive:
```
mcp__tkn-toolhelper__list_tool_servers()    # or equivalent health check
```

For specific servers:
```
mcp__tkn-arr__arr_health_check()
mcp__tkn-authentik__authentik_health_check()
```

## Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `mcp-image` not running | Not set to auto-start | Start + enable auto-start |
| Init container stuck | One-shot task didn't clean up | Delete and recreate |
| Container exits immediately | Config/volume issue | Check logs, verify mounts |
| HITL approval broken | Redis or HITL container down | Restart `mcp-hitl` and `redis` stacks |

## Key Container Names

- `mcp-*` — MCP server containers
- `redis` — Used by HITL and other services
- `jellyfin`, `plex` — Media servers
- `sonarr`, `radarr`, `prowlarr`, `bazarr` — Media stack
- `authentik-*` — Auth containers (restart in order: db → redis → server → worker)

## Pitfalls

- Don't delete containers unless they're genuinely broken — `restart_container` is usually enough
- Init containers (`-app` suffix, `Exited (0)`) are normal — don't restart them
- If Authentik fails, restart its components in dependency order: postgresql → redis → server → worker
- After a network stack restart, containers that depend on a custom Docker network may need to be stopped and started (not just restarted)
