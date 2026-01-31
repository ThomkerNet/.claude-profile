## Claude Profile

Load `/profile-reference` for detailed docs on any feature.

---

## Critical Rules

1. **Before deploying:** Read `DEPLOYMENT.md` or `ARCHITECTURE.md` in project/parent dirs, or ask
2. **Before creating patterns:** Check sibling repos first (same org = tightly coupled)
3. **Never** change system passwords without explicit instruction
4. **Credentials:** Use `/bw-ref` for vault architecture, never hardcode secrets

---

## Infrastructure

| Domain | Stack |
|--------|-------|
| **BriefHours** | Azure UK South (Container Apps, PostgreSQL Flexible, Azure OpenAI) |
| **Other projects** | Mac Mini cluster, Cloudflare Tunnels, self-hosted PostgreSQL, Docker |
| **NOT** | Vercel, AWS, cloud PaaS (unless project-specific) |

---

## Repository Structure

```
~/git-bnx/
├── TKN/          # Personal/homelab (unrelated to work)
├── BNX/          # BoroughNexus company
└── BriefHours/   # BriefHours product (cousin of BNX)
```

**Coupling:** Siblings (same org) = tightly coupled. Cousins (BNX↔BriefHours) = may diverge.

---

## GitHub Accounts

If push fails "repository not found":
```bash
gh auth switch --user <ample-engineer|boroughnexus-cto>
```

| Account | Use |
|---------|-----|
| `ample-engineer` | Personal, ~/.claude profile |
| `boroughnexus-cto` | Work projects |

---

## Memory

**Store on:** "I prefer", "always", "never", "remember", architecture decisions, corrections

**Session start:** `search_nodes("user")` and `search_nodes("<project>")`

---

## Obsidian Vault

**Location:** `~/personal-obsidian/` (git repo, auto-syncs)

**Access method:** Direct file operations - Read, Write, Edit, Grep, Glob

```bash
# Read a note
Read ~/personal-obsidian/Projects/BoroughNexus/Index.md

# Search for content
Grep "search term" ~/personal-obsidian/

# Find notes
Glob "**/*.md" ~/personal-obsidian/Projects/
```

**Structure:** PARA method - `Projects/`, `Areas/`, `Resources/`, `Archive/`

**Key folders:**
- `Projects/BoroughNexus/AI-Claude/` - Claude tooling docs
- `Projects/BriefHours/` - BriefHours product
- `Projects/TKN/` - Homelab/personal

**When documenting:** Use `[[WikiLinks]]` for cross-references, append to existing notes when possible.

---

## Reference Skills (load as needed)

| Skill | Content |
|-------|---------|
| `/profile-reference` | MCP servers, router, statusline |
| `/todoist-ref` | API examples, project IDs |
| `/bw-ref` | Two-vault architecture, credential access |
| `/obsidian-ref` | Full vault structure, PARA details |

---

## Quick Reference

| Item | Value |
|------|-------|
| Profile repo | `~/.claude-profile/` (git) → `~/.claude/` (symlinks) |
| Homelab docs | `~/git-bnx/TKN/TKNet-Homelab-Docs/` |
| "ppp" | Puppeteer |

---

## Contacts

| Person | Role |
|--------|------|
| Simon | User (simonbarker@gmail.com) |
| Charlotte | Partner, co-runs BNX |
