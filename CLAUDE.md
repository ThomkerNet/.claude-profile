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
| `/zcicd` | Zero-friction commit with CI/CD monitoring and auto-fix |
| `/zdoc` | Zero-friction commit with Obsidian documentation |
| `/zmcpbacklog` | Analyze session for MCP server opportunities |
| `/imagen` | Generate images via Azure DALL-E 3 / Gemini |
| `/tts` | Text-to-speech via Azure AI Speech |
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

## MCP Server Connectivity

TKN MCP servers connect via **Tailscale HTTPS** using streamable-http transport:
```
claude mcp add <name> --transport http https://mcp-<name>.gate-hexatonic.ts.net/mcp
```

All server URLs are defined in `~/.claude-profile/mcp-servers.json`. Use `/zupdatetknmcpservers` to sync with deployed servers.

---

## AI Peer Review (MCP Server: `tkn-aipeerreview`)

Multi-model code review and consultation via external AI models. Use this to get second opinions from non-Claude models (GPT-5.2, Gemini 3 Pro, Codex, etc.).

**When to use:**
- User asks to "peer review", "get a second opinion", or "review this code"
- Before merging significant changes (architecture, security-sensitive code)
- Debugging hard problems — consult external models for fresh perspective

### Quick Reference

| Tool | Use When | Speed |
|------|----------|-------|
| `quick_review` | Fast feedback on a code snippet | ~10s |
| `peer_review` | Thorough multi-model review | ~30-60s |
| `quick_consult` | Quick question to an external model | ~10s |
| `peer_consult` | Deep consultation on a problem | ~30-60s |

### Review Types

Use `detect_review_type` to auto-detect, or specify directly:

| Type | Best For |
|------|----------|
| `security` | Auth, input validation, secrets, OWASP |
| `architecture` | Design patterns, coupling, scalability |
| `bug` | Logic errors, edge cases, race conditions |
| `performance` | Bottlenecks, memory, algorithmic complexity |
| `api` | REST/GraphQL design, contracts, versioning |
| `test` | Coverage, assertions, test quality |
| `general` | Broad review (default) |

### Consultation Types

Use `detect_consultation_type` to auto-detect, or specify directly:

`debugging`, `architecture`, `implementation`, `explanation`, `code-understanding`, `security`, `optimization`, `general`

### Model Selection

Use `get_models_for_review_type` or `get_models_for_consultation_type` to see available models. Key models:
- **`gpt-5.2`** / **`gpt-5.2-codex`** — Strong for practical code fixes
- **`gemini-3-pro-preview`** — Good architectural perspective
- **`claude-opus-4-5`** — When you want a Claude second opinion

Omit `model` parameter to use the server's default selection.

### Fallback Behavior

The server has **API fallback** — if primary model provider is unavailable, it automatically routes to an available alternative. No client-side handling needed.

### Examples

```
# Quick review of a function
quick_review(content: "...")

# Thorough security review with specific model
peer_review(content: "...", review_type: "security", model: "gpt-5.2")

# Consult on a debugging problem
peer_consult(question: "Why might this race condition occur?", context: "...", consultation_type: "debugging")
```

---

## Fabric Pattern Library (MCP Server: `tkn-fabric`)

Expert prompt enhancement and AI task dispatch via the [Fabric](https://github.com/danielmiessler/fabric) pattern library (251 patterns). Use this to frame work through the right expert lens before executing, or to dispatch a fully-structured task to SwarmOps.

**When to use:**
- User asks to "use fabric", "enhance this prompt", or "find a pattern for X"
- Before starting a complex task — find the best expert framing first
- User wants to dispatch a task to SwarmOps with a fabric-enhanced brief
- Improving a vague or underspecified instruction into a structured prompt

### Quick Reference

| Tool | Use When |
|------|----------|
| `select_pattern` | Find the best pattern for an intent (TF-IDF + LLM reranking) |
| `get_pattern` | Read full system prompt for a named pattern |
| `enhance_prompt` | Rewrite a prompt using the best matching pattern |
| `list_patterns` | Browse all 251 available patterns |
| `create_dispatch_pack` | Build a structured task brief (pattern + context + goals) for SwarmOps |
| `create_swarmops_task` | Send a dispatch pack directly to SwarmOps for agent execution |
| `update_patterns` | Refresh the pattern index from the upstream fabric repo |

### Workflow

```
# Find and apply the best pattern
select_pattern(intent: "analyse security of this API")
→ returns ranked patterns with scores

# Enhance a prompt directly
enhance_prompt(prompt: "review my auth code", top_k: 3)
→ returns rewritten prompt using best pattern

# Dispatch to SwarmOps
create_dispatch_pack(intent: "refactor this module", context: "...", goals: ["..."])
→ create_swarmops_task(dispatch_pack: <result>)
```

### Pattern Selection

`select_pattern` uses TF-IDF for fast candidate retrieval then LiteLLM reranking for accuracy. Pass `top_k` (default 5) to control how many candidates are returned. The best match is `results[0]`.

---

## Notes

- **Scratchpad for temp files:** Use session-specific scratchpad directory (not `/tmp`)
- **Documentation style:** Append to existing docs when possible, create new files sparingly
- **WikiLinks in Obsidian:** Use `[[Note-Name]]` format for cross-references
- **Abbreviation:** "ppp" = Puppeteer
