## Claude Profile

For detailed docs: load `profile-reference` skill or ask about specific feature.

---

## Directory Structure

**Claude Profile:**
```
~/.claude-profile/     # Git repo (version controlled) - this repo
~/.claude/             # Active profile (symlinks to above + runtime files)
```

**Code Repositories** (`~/git-bnx/`):
```
~/git-bnx/
├── TKN/              # ThomkerNet org (personal/homelab)
│   ├── TKNet-Homelab-Docs/
│   ├── .claude-profile/
│   └── ...
├── BNX/              # BoroughNexus org (company)
│   ├── BNX-MacMini-BareMetal-Setup/
│   ├── BNX-Web/
│   └── ...
└── BriefHours/       # BriefHours org (product)
    ├── BriefHours-App/
    ├── BriefHours-Web/
    └── ...
```

**Setup:** Run `./setup-repos.sh` to clone all org repos (auto-discovers from GitHub).

**Project Relationships:**
- **Siblings** = Same parent org (can share code/patterns directly)
  - `BriefHours-App` ↔ `BriefHours-Web` (both under BriefHours/)
  - `BNX-Web` ↔ `BNX-Docs-Architecture` (both under BNX/)
- **Cousins** = Same grandparent (BoroughNexus is parent company)
  - `BriefHours/*` ↔ `BNX/*` (BriefHours is a BNX product)
  - Share infrastructure patterns, credentials, deployment approaches
- **Unrelated** = Different family (ThomkerNet is personal, not BNX)
  - `TKN/*` repos are Simon's personal/homelab, separate from work

**Pattern coupling:**
- Siblings should stay **tightly coupled** - same conventions, shared utilities, consistent patterns
- Cousins **may diverge** - different tech stacks or approaches are acceptable if justified
- Always check siblings first before creating new patterns

---

## CRITICAL: Deployment Rules

**NEVER assume deployment targets.** Before deploying:

1. Check: `ARCHITECTURE.md`, `DEPLOYMENT.md`, `docs/` in project/parent dirs
2. Search: `find ~/git-bnx -name "*deploy*" 2>/dev/null | head -10`
3. Ask if not found: "Where should this deploy?"

**Simon's infra:**
- **BriefHours:** 100% Azure UK South (Container Apps, PostgreSQL Flexible, Azure OpenAI)
- **Other projects:** Mac Mini cluster, Cloudflare Tunnels, self-hosted PostgreSQL (Patroni), Docker
- **NOT:** Vercel/AWS/cloud PaaS (unless project-specific)

---

## Multi-LLM Tools

| Tool | Use | Command |
|------|-----|---------|
| **Claude** | Complex coding, refactoring, architecture | (current) |
| **Copilot** | Peer review, second opinions, multi-model | `copilot -p "..."` |
| **Gemini** | Multimodal only (images, PDFs) | `gemini -p "..."` |

**Copilot models:** `--model claude-opus-4.5`, `--model gpt-5.1`, `--model gemini-3-pro-preview`

**Fallback:** If Copilot unavailable, use `gemini -p "..."` directly.

Call multiple in parallel when comparing (multiple Bash tools in one message).

---

## GitHub Accounts

Simon uses multiple GitHub accounts. If push fails with "repository not found":

```bash
gh auth status          # Check active account
gh auth switch --user <account>  # Switch accounts
```

| Account | Use |
|---------|-----|
| `ample-engineer` | Personal projects, ~/.claude profile |
| `boroughnexus-cto` | Work projects |

---

## Memory (USE PROACTIVELY)

**Store automatically:** preferences, corrections, project patterns, decisions.

**Session start:** `search_nodes("user")` and `search_nodes("<project>")`

**Store:** `create_entities([{name:"user", entityType:"person", observations:["Prefers X"]}])`
**Add:** `add_observations([{entityName:"user", contents:["New pref"]}])`

---

## MCP Quick Reference

| Server | Use |
|--------|-----|
| **Context7** | Library docs (`resolve-library-id` → `query-docs`) |
| **Firecrawl** | Web scraping/search (prefer over WebFetch) |
| **Puppeteer** | Browser automation, screenshots ("ppp") |
| **Memory** | Persistent knowledge graph |

---

## Commands

| Cmd | Purpose |
|-----|---------|
| `/q` | Queue task for later |
| `/qa` | Add to current scope |
| `/qq` | Show queue |
| `/qn` | Start next |
| `/z` | Commit + push |
| `/review` | Solution review |
| `/imagen` | Generate images |

---

## Image Generation

**Skill:** `/imagen` or natural language ("generate an image of...")

**Workflow:** Clarify intent → Build spec → Confirm → Generate → Iterate

**API:** Gemini native image generation (`gemini-2.5-flash-preview-05-20`)

**Credential:** `GEMINI_API_KEY` env var (get from https://aistudio.google.com/apikey)

**Output:** `~/.claude/output/images/`

---

## Router

Sonnet (default) → Haiku (simple) → Opus (architecture/planning). Auto-routed by Claude Code Router.

---

## Homelab

Docs: `~/git-bnx/TKN/TKNet-Homelab-Docs/` | Secrets: `secrets.env` in that dir.

For Cloudflare tunnel/access setup, check `services/cloudflare.md`.

---

## Obsidian (Knowledge Management)

**Vault:** `~/Obsidian/Simon-Personal/`

**Access:** Direct file operations (no MCP needed - vault is just markdown files)
- Read/Write/Edit/Grep/Glob work directly on `.md` files
- No Obsidian REST API plugin required

**Structure (PARA):**
```
Projects/
  BoroughNexus/       # Parent company
    AI-Claude/        # Claude tooling docs
  BriefHours/         # Voice time-tracking product (sibling, not subfolder)
    Index.md          # Project overview
    Backlog.md        # Roadmap and features
    Architecture.md   # Technical architecture summary
Areas/
  Personal/           # Charlotte, Social, Tax (encrypted)
  Hobbies/            # Comedy Course
  Life/               # Travel SOPs, Scuba
Resources/
  DnD/                # D&D 5e SRD
  Oxford MSc/         # Cybersecurity course notes
Archive/              # Inactive items
attachments/          # Images, PDFs
```

**Sync:** Obsidian Sync (paid) → iOS/Mac/Windows
**Plugins:** Meld Encrypt (sensitive data), Todoist Sync

**Basalt TUI:** Terminal interface for Obsidian
- Run: `basalt`
- Binary: `~/.cargo/bin/basalt`

---

## Todoist (Task Management)

**API:** REST v2 + Sync v9
**Credential:** Bitwarden → "Todoist" → field "API Key"

**Workflow:** First retrieve API key from Bitwarden (`bw get item "Todoist" | jq -r '.fields[] | select(.name=="API Key") | .value'`), then use in curl commands below.

**Projects:**
| Project | ID | Purpose |
|---------|-----|---------|
| Inbox | 2310975157 | Quick capture |
| Personal | 2314378138 | Solo: MSc, health, hobbies |
| Thomker Home | 2364972779 | Shared w/ Charlotte: house, life admin |

**Key Operations:**
```bash
# List tasks
curl -s "https://api.todoist.com/rest/v2/tasks?project_id=<id>" \
  -H "Authorization: Bearer $TODOIST_API_KEY"

# Create task
curl -s -X POST "https://api.todoist.com/rest/v2/tasks" \
  -H "Authorization: Bearer $TODOIST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"content":"Task","project_id":"<id>","due_string":"tomorrow"}'

# Move task (Sync API)
curl -s -X POST "https://api.todoist.com/sync/v9/sync" \
  -H "Authorization: Bearer $TODOIST_API_KEY" \
  -d 'commands=[{"type":"item_move","uuid":"<uuid>","args":{"id":"<task_id>","project_id":"<target_id>"}}]'
```

---

## Bitwarden (Credential Access)

**Two-vault architecture:**

| Vault | Server | Access Model |
|-------|--------|--------------|
| **TKN** (personal) | vaultwarden.thomker.net | Operator-driven (`bw-tkn`) |
| **BNX** (work) | vault.boroughnexus.com | Claude autonomous (RO via Keychain) |

**BNX Autonomous Access (claude@boroughnexus.com):**
- Service account with RO collection access only
- API key stored in macOS Keychain (Secure Enclave)
- Setup: `bun run ~/.claude/tools/vaultwarden/setup-keychain.ts`
- Claude uses: `bun run ~/.claude/tools/vaultwarden/bw-wrapper.ts api-get "name"`

**TKN Manual Access (simonbarker@gmail.com):**
- Operator unlocks, passes session to Claude
- Wrapper: `bw-tkn` in `~/.claude/tools/bitwarden/`
```bash
bw-tkn login              # First-time setup
bw-tkn unlock --raw       # Generate session for Claude
bw-tkn lock               # After session ends
```

**RW Operations (either vault):**
- Require elevation: `bun run ~/.claude/tools/vaultwarden/bw-elevate.ts`
- Collections: `bnx-infra`, `bnx-secrets`, `briefhours-deploy`

---

## Key Contacts

| Person | Email | Relationship |
|--------|-------|--------------|
| Simon | simonbarker@gmail.com | User |
| Charlotte | charlottemtthomas@gmail.com | Partner, co-runs BNX, shares Thomker Home |

---

## Notes

- **Never** change system passwords without explicit instruction
- "ppp" = Puppeteer
- BW session tokens expire on `bw lock` or new terminal
- Sensitive Obsidian content uses Meld Encrypt
- Claude integration docs: `~/Obsidian/Simon-Personal/Projects/BoroughNexus/AI-Claude/`
- BriefHours project docs: `~/Obsidian/Simon-Personal/Projects/BriefHours/`
