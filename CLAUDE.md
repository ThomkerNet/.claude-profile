# Claude Profile

> **Quick Start:** This profile manages context for BoroughNexus, BriefHours, and homelab projects.

Load `/profile-reference` for detailed docs on MCP servers, router, and statusline features.

---

## Navigation

### Policies (Must Follow)

| File | Purpose |
|------|---------|
| [SECURITY.md](policies/SECURITY.md) | Credential management, secrets handling, security best practices |
| [DEPLOYMENT.md](policies/DEPLOYMENT.md) | Pre-deployment requirements, deployment gating, rollback procedures |
| [COUPLING.md](policies/COUPLING.md) | Repository dependencies, shared code patterns, interface contracts |

### Architecture (How Things Work)

| File | Purpose |
|------|---------|
| [INFRASTRUCTURE.md](architecture/INFRASTRUCTURE.md) | Cloud environments, hosting platforms, infrastructure decisions |
| [TOPOLOGY.md](architecture/TOPOLOGY.md) | Repository organization, project relationships, directory structure |

### Operations (Day-to-Day)

| File | Purpose |
|------|---------|
| [RUNBOOK.md](operations/RUNBOOK.md) | Common commands, workflows, troubleshooting procedures |
| [OBSIDIAN.md](operations/OBSIDIAN.md) | Knowledge management, note-taking, vault structure |

### Reference (Quick Lookup)

| File | Purpose |
|------|---------|
| [QUICK_REF.md](reference/QUICK_REF.md) | Paths, contacts, shortcuts, frequently needed information |

---

## Critical Rules

**These are ALWAYS enforced:**

1. **Never** change system passwords without explicit instruction
2. **Never** hardcode secrets → Use Bitwarden (see [SECURITY.md](policies/SECURITY.md))
3. **Before deploying:** Check for DEPLOYMENT.md in project root, or ask user
4. **Before cross-repo imports:** Review [COUPLING.md](policies/COUPLING.md) for proper patterns

---

## Quick Context

### Repository Structure

```
~/git-bnx/
├── TKN/          # Personal/homelab (independent from work)
├── BNX/          # BoroughNexus company projects
└── BriefHours/   # BriefHours product (cousin of BNX)
```

**Relationships:**
- **TKN ↔ BNX/BriefHours:** No shared code
- **BNX ↔ BriefHours:** Cousins - may share patterns, but codebases diverge
- **BNX siblings:** Share code via versioned packages only

See [TOPOLOGY.md](architecture/TOPOLOGY.md) for details.

---

### Infrastructure Summary

| Project | Platform | Database | Deployment |
|---------|----------|----------|------------|
| **BriefHours** | Azure UK South | PostgreSQL Flexible | Container Apps |
| **BNX/Other** | Homelab (Mac Mini) | Self-hosted PostgreSQL | Docker Compose |

See [INFRASTRUCTURE.md](architecture/INFRASTRUCTURE.md) for details.

---

### Git Configuration

**Single account for all projects:** `boroughnexus-cto`

```ini
[user]
  name = Simon Barker
  email = simon@boroughnexus.com
[github]
  user = boroughnexus-cto
```

No account switching needed (simplified from previous multi-account setup).

---

## Skills (Load as Needed)

Load with `/<skill-name>`:

| Skill | Content |
|-------|---------|
| `/profile-reference` | MCP servers, router, statusline (Claude profile features) |
| `/bwdangerunlock` | Full Bitwarden vault access (operator places session token) |
| `/obsidian-ref` | Full vault structure, PARA method details |
| `/todoist-ref` | Todoist API examples, project IDs |
| `/ultrathink` | Extended reasoning for complex problems |
| `/z` | Zero-friction commit with AI-generated messages |
| `/imagen` | Generate images via Google Gemini |
| `/zupdatetknmcpservers` | Sync deployed TKN MCP servers to claude-profile config |

---

## Memory (MCP Server)

**Store in memory:**
- User preferences: "I prefer X", "always do Y", "never do Z"
- Architecture decisions and patterns
- Corrections and learnings

**Session start queries:**
```typescript
search_nodes("user")              // Load personal preferences
search_nodes("BoroughNexus")      // If working in BNX project
search_nodes("BriefHours")        // If working in BriefHours project
```

---

## Obsidian Vault

**Location:** `~/personal-obsidian/` (git-backed, auto-syncs)

**Access:** Direct file operations (Read, Write, Edit, Grep, Glob)

**Structure:** PARA method - `Projects/`, `Areas/`, `Resources/`, `Archive/`

**Key folders:**
- `Projects/BoroughNexus/AI-Claude/` - Claude tooling documentation
- `Projects/BriefHours/` - BriefHours product notes
- `Projects/TKN/` - Homelab and personal projects

**Best practice:** Scope searches to specific projects to avoid context leakage.

See [OBSIDIAN.md](operations/OBSIDIAN.md) for detailed usage.

---

## Quick Reference

| Item | Path |
|------|------|
| **Claude profile repo** | `~/.claude-profile/` (git) → `~/.claude/` (symlinks) |
| **Git repositories** | `~/git-bnx/` |
| **Homelab documentation** | `~/git-bnx/TKN/TKNet-Homelab-Docs/` |
| **Obsidian vault** | `~/personal-obsidian/` |

| Person | Role | Email |
|--------|------|-------|
| **Simon** | User, Developer | simonbarker@gmail.com |
| **Charlotte** | Partner, Co-runs BNX | (ask if needed) |

See [QUICK_REF.md](reference/QUICK_REF.md) for more shortcuts and paths.

---

## Common Tasks

### Start Working on a Project

1. Navigate to project: `cd ~/git-bnx/BNX/project-name`
2. Check git status: `git status`
3. Load project context from memory: `search_nodes("project-name")`
4. Review project's README, DEPLOYMENT.md, ARCHITECTURE.md if they exist

### Deploy Changes

1. **Read** project's `DEPLOYMENT.md` or ask user
2. Run tests, linting
3. Follow environment-specific procedures (see [DEPLOYMENT.md](policies/DEPLOYMENT.md))
4. Verify deployment with health checks

### Manage Credentials

1. **Never** hardcode secrets
2. Load credential from Bitwarden (use `/bwdangerunlock` when session token available)
3. Use environment variables in code
4. See [SECURITY.md](policies/SECURITY.md) for complete procedures

### Share Code Between BNX Projects

1. Extract to shared library: `~/git-bnx/BNX/shared-{name}/`
2. Publish as `@boroughnexus/{name}` package
3. Version using semver
4. See [COUPLING.md](policies/COUPLING.md) for patterns

---

## Getting Help

- **Claude profile features:** Load `/profile-reference`
- **General Claude Code help:** Use `/help` command
- **Report issues:** https://github.com/anthropics/claude-code/issues
- **Documentation:** See navigation table above

---

## MCP Server Connectivity (CRITICAL)

**Nginx path-prefix proxying BREAKS MCP SSE protocol.** Do NOT use URLs like `http://10.0.0.2:8000/tkn-server/sse`.

**Root cause:** MCP servers return absolute paths (`/messages/?session_id=xxx`) in SSE responses. When behind an nginx path-prefix proxy (`/tkn-server/`), the client resolves `/messages/` against the host root, losing the prefix. The POST to `/messages/` hits nginx's default handler instead of the MCP server.

**Correct pattern:** Connect directly to container ports via `mcp-remote`:
```
npx -y mcp-remote http://10.0.0.2:<PORT>/sse --allow-http
```

| Server | Port | URL |
|--------|------|-----|
| tkn-cloudflare | 8200 | `http://10.0.0.2:8200/sse` |
| tkn-unraid | 8201 | `http://10.0.0.2:8201/sse` |
| tkn-aipeerreview | 8202 | `http://10.0.0.2:8202/sse` |

**Never** route MCP connections through nginx path-prefix proxy. Always use direct port access.

---

## Notes

- **Scratchpad for temp files:** Use session-specific scratchpad directory (not `/tmp`)
- **Documentation style:** Append to existing docs when possible, create new files sparingly
- **WikiLinks in Obsidian:** Use `[[Note-Name]]` format for cross-references
- **Abbreviation:** "ppp" = Puppeteer
