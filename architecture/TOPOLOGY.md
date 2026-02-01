# Repository Topology

**Scope:** Repository organization, directory structure, project relationships

---

## Directory Structure

```
~/git-bnx/
├── TKN/                    # Personal & homelab projects
│   ├── TKNet-Homelab-Docs/ # Infrastructure documentation
│   └── ...                 # Other personal projects
│
├── BNX/                    # BoroughNexus company
│   └── ...                 # Client projects, internal tools
│
└── BriefHours/             # BriefHours product
    └── ...                 # SaaS application, related services
```

---

## Project Classification

### TKN (Personal/Homelab)

**Purpose:** Personal learning, homelab infrastructure, experimentation

**Characteristics:**
- Independent from work projects
- Self-hosted on Mac Mini cluster
- No shared code with BNX/BriefHours
- Personal experimentation and learning

**Examples:**
- `TKNet-Homelab-Docs`: Infrastructure documentation
- Personal automation scripts
- Homelab monitoring dashboards
- Experimental projects

**Infrastructure:** Homelab (see `~/.claude/architecture/INFRASTRUCTURE.md`)

---

### BNX (BoroughNexus Company)

**Purpose:** Client projects, internal tools, company work

**Characteristics:**
- Professional work for BoroughNexus
- May be client-specific or internal
- Can share patterns/libraries within BNX org
- Separate from BriefHours product

**Infrastructure:** Depends on project (homelab or client-specified)

**Coupling:** Sibling BNX projects may share code via published packages (see `~/.claude/policies/COUPLING.md`)

---

### BriefHours (Product)

**Purpose:** BriefHours SaaS product and related services

**Characteristics:**
- Production SaaS application
- Related to BNX but separate codebase
- Azure-hosted infrastructure
- Independent deployment and versioning

**Infrastructure:** Azure UK South (see `~/.claude/architecture/INFRASTRUCTURE.md`)

**Coupling:** Cousin relationship with BNX - can share patterns but codebases diverge

---

## Organizational Relationships

```
TKN
 └── (no relationship) ───────┐
                              │
BNX                           │
 ├── project-a                │
 ├── project-b                │  All independent
 └── project-c                │
     (siblings: managed coupling) │
                              │
BriefHours                    │
 └── (cousin to BNX) ─────────┘
     (can diverge)
```

### Relationship Matrix

| From → To | TKN | BNX Projects | BriefHours |
|-----------|-----|--------------|------------|
| **TKN** | Internal only | ❌ No sharing | ❌ No sharing |
| **BNX Projects** | ❌ No sharing | ✅ Via packages | ⚠️ Patterns only |
| **BriefHours** | ❌ No sharing | ⚠️ Patterns only | Internal only |

**Legend:**
- ✅ Via packages: Share code through published npm packages
- ⚠️ Patterns only: Share architectural patterns and learnings, not code
- ❌ No sharing: Completely independent

---

## Git Configuration

**All projects use the same GitHub account now:** `boroughnexus-cto`

**Global git configuration (~/.gitconfig):**
```ini
[user]
  name = Simon Barker
  email = simon@boroughnexus.com

[github]
  user = boroughnexus-cto

[init]
  defaultBranch = main

[pull]
  rebase = true
```

**No account switching needed** - simplified from previous multi-account setup.

---

## Branching Strategy

### Default: GitHub Flow (Simplified)

For most projects:

```
main (production/deployable)
  ↑
feature/fix branches
```

**Workflow:**
1. Branch from `main`: `feature/add-login` or `fix/api-timeout`
2. Make changes, commit frequently
3. Push and create Pull Request
4. Review, test, merge to `main`
5. Deploy from `main`

---

### For BriefHours (if needed): GitFlow

If more structured releases needed:

```
main (production)
  ↑
develop (integration)
  ↑
feature/fix branches
```

**Workflow:**
1. Branch from `develop`
2. Merge to `develop` when ready
3. Release branch from `develop` → `main`
4. Hotfixes branch from `main` → back to `main` + `develop`

---

## Repository Naming Conventions

### BNX Projects

```
~/git-bnx/BNX/
├── client-projectname/     # Client work
├── internal-toolname/      # Internal tools
└── shared-packagename/     # Shared libraries (@boroughnexus/*)
```

**Examples:**
- `client-councilwebsite`
- `internal-timesheets`
- `shared-ui-components` → `@boroughnexus/ui-components`

---

### BriefHours

```
~/git-bnx/BriefHours/
├── briefhours-api/         # Main API
├── briefhours-web/         # Web frontend
└── briefhours-ai/          # AI/ML services
```

Or potentially a monorepo:
```
~/git-bnx/BriefHours/briefhours-platform/
├── apps/
│   ├── api/
│   └── web/
└── packages/
    └── shared/
```

---

### TKN (Personal)

```
~/git-bnx/TKN/
├── TKNet-Homelab-Docs/     # Infrastructure docs
├── automation-scripts/      # Bash/Python scripts
└── experiment-projectname/  # Learning projects
```

**Naming:** Freeform, optimized for personal clarity

---

## .gitignore Patterns

**Standard across all projects:**

```gitignore
# Dependencies
node_modules/
venv/
.venv/

# Environment & secrets
.env
.env.local
*.env
credentials.json
secrets/

# Build artifacts
dist/
build/
*.log

# IDE
.vscode/
.idea/
*.swp

# OS
.DS_Store
Thumbs.db

# Project-specific (add as needed)
```

---

## README Standards

Every repository should have a `README.md` with:

```markdown
# Project Name

Brief description of what this project does.

## Prerequisites
- Node.js 18+
- PostgreSQL 14+
- etc.

## Setup
1. Clone the repo
2. Install dependencies: `npm install`
3. Configure environment: `cp .env.example .env`
4. Run: `npm run dev`

## Deployment
See DEPLOYMENT.md (or brief instructions)

## Architecture
See ARCHITECTURE.md (or link to docs)
```

---

## Documentation Structure

Each project may contain:

```
project-root/
├── README.md              # Overview, quick start
├── ARCHITECTURE.md        # System design (if complex)
├── DEPLOYMENT.md          # Deployment procedures
├── CONTRIBUTING.md        # Contribution guidelines (if team)
├── docs/
│   ├── adr/               # Architectural Decision Records
│   └── api.md             # API documentation
└── .env.example           # Environment variable template
```

---

## Shared Libraries (BNX Only)

**Location:** `~/git-bnx/BNX/shared-{name}/`

**Publishing:** NPM packages under `@boroughnexus/*` scope

**Structure:**
```
~/git-bnx/BNX/shared-utils/
├── package.json           # "@boroughnexus/shared-utils"
├── src/
│   ├── index.ts           # Main exports
│   └── utils/
├── tests/
├── README.md              # API documentation
└── CHANGELOG.md           # Version history
```

**Versioning:** Semantic versioning (semver)

**See:** `~/.claude/policies/COUPLING.md` for usage guidelines

---

## Monorepo Considerations

**When to use monorepo:**
- Multiple tightly-coupled services
- Shared build/test/deploy pipeline
- Atomic cross-service changes needed

**Tools:**
- Nx
- Turborepo
- Yarn/npm workspaces

**Example structure:**
```
~/git-bnx/BNX/platform-monorepo/
├── package.json           # Workspace root
├── apps/
│   ├── api/
│   ├── web/
│   └── worker/
├── packages/
│   ├── ui-components/
│   ├── shared-types/
│   └── utils/
└── tools/
    └── scripts/
```

**See:** `~/.claude/policies/COUPLING.md` for coupling decisions

---

## Migration Paths

### Moving Between Orgs

**TKN → BNX/BriefHours:**
- Extract into new repo
- Remove personal/homelab-specific config
- Add professional documentation
- Update infrastructure references

**BNX ↔ BriefHours:**
- Fork or create new repo (don't share git history if diverging)
- Document architectural differences
- Plan for independent evolution

---

## Archival Process

**For deprecated projects:**

1. Add `[ARCHIVED]` to repo description
2. Create `ARCHIVED.md` explaining why and what replaced it
3. Make repo read-only on GitHub
4. Move to `Archive/` subdirectory locally (optional)
5. Note in Obsidian vault under `Archive/` folder

---

## Quick Reference

| Concept | Location |
|---------|----------|
| **Homelab docs** | `~/git-bnx/TKN/TKNet-Homelab-Docs/` |
| **Shared libraries** | `~/git-bnx/BNX/shared-*/` |
| **Claude profile** | `~/.claude-profile/` (git) → `~/.claude/` (symlinks) |
| **Obsidian vault** | `~/personal-obsidian/` (git-backed) |

---

## Questions?

- Coupling between repos: See `~/.claude/policies/COUPLING.md`
- Infrastructure per project: See `~/.claude/architecture/INFRASTRUCTURE.md`
- Deployment processes: See `~/.claude/policies/DEPLOYMENT.md`
