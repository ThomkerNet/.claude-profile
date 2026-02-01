# Obsidian Vault Operations

**Scope:** Knowledge management, note-taking, vault structure and access

---

## Vault Location

**Path:** `~/personal-obsidian/`

**Characteristics:**
- Git-backed repository (auto-syncs)
- PARA method organization
- Mix of work and personal notes (with clear separation)

---

## Access Method

**Direct file operations** using Claude Code tools:

```bash
# Read a note
Read ~/personal-obsidian/Projects/BoroughNexus/Index.md

# Search for content
Grep "search term" ~/personal-obsidian/Projects/BoroughNexus/

# Find notes by pattern
Glob "**/*.md" ~/personal-obsidian/Projects/BriefHours/

# Edit existing note
Edit ~/personal-obsidian/Areas/Development/Claude-Workflows.md
```

**Important:** Always scope searches to specific Projects or Areas when possible to avoid context leakage between unrelated notes.

---

## PARA Structure

**PARA = Projects, Areas, Resources, Archive**

```
~/personal-obsidian/
├── Projects/              # Active projects with end date
│   ├── BoroughNexus/
│   │   ├── Index.md
│   │   └── AI-Claude/    # Claude tooling documentation
│   ├── BriefHours/
│   └── TKN/              # Homelab/personal projects
│
├── Areas/                # Ongoing responsibilities
│   ├── Development/
│   ├── Health/
│   └── Finance/
│
├── Resources/            # Reference material
│   ├── Technical/
│   └── Learning/
│
└── Archive/              # Completed or inactive items
    ├── Projects/
    └── Areas/
```

---

## Key Folders

### Projects/BoroughNexus/

**Purpose:** BNX company work, client projects, documentation

**Structure:**
```
Projects/BoroughNexus/
├── Index.md                 # Overview and navigation
├── AI-Claude/               # Claude Code tooling, profiles, scripts
│   ├── Profile-Setup.md
│   ├── MCP-Servers.md
│   └── Skills.md
├── Clients/                 # Client-specific notes
└── Internal/                # Internal tools and processes
```

**When to update:** Architecture decisions, learnings, client requirements

---

### Projects/BriefHours/

**Purpose:** BriefHours product development, features, decisions

**Structure:**
```
Projects/BriefHours/
├── Index.md                 # Product overview
├── Architecture/            # System design, ADRs
├── Features/                # Feature planning and specs
└── Releases/                # Release notes and planning
```

**When to update:** Product decisions, feature specs, architecture changes

---

### Projects/TKN/

**Purpose:** Personal homelab, experiments, learning projects

**Structure:**
```
Projects/TKN/
├── Index.md                 # Homelab overview
├── Infrastructure/          # Server setup, networking
├── Automation/              # Scripts, workflows
└── Experiments/             # Learning and testing
```

**When to update:** Homelab changes, experiment results, learning notes

---

## WikiLinks Convention

**Use double-bracket links** for cross-references:

```markdown
See [[Claude-Workflows]] for automation details.

Related: [[BoroughNexus/Clients/Council-Website]]
```

**Benefits:**
- Easy navigation in Obsidian app
- Automatic backlink creation
- Refactoring support

---

## When to Document

### Always Document

- **Architecture decisions:** Major technology choices, design patterns
- **User preferences:** "I prefer X", "always do Y", "never do Z"
- **Learnings:** Solutions to problems, gotchas discovered
- **Process changes:** New workflows, improved procedures

### Consider Documenting

- **Complex implementations:** Multi-step processes that may be repeated
- **Incident resolutions:** How you fixed production issues
- **Research findings:** Investigation results, comparisons

### Don't Document

- **Trivial changes:** One-line fixes, typo corrections
- **Temporary notes:** Quick reminders (use scratch files instead)
- **Sensitive data:** Credentials, secrets (use Bitwarden)

---

## Documentation Patterns

### Append to Existing Notes

**Preferred approach:** Add to relevant existing notes rather than creating new ones.

```markdown
# Example: Appending to Projects/BoroughNexus/AI-Claude/Profile-Setup.md

## 2024-01-15: Improved Memory Usage

Discovered that scoped `search_nodes()` queries work better:
- `search_nodes("BoroughNexus")` when in BNX projects
- `search_nodes("BriefHours")` when in BriefHours
- Avoids context leakage between projects

See: ~/.claude/operations/OBSIDIAN.md
```

---

### Create New Notes

**When appropriate:**
- New project started
- New major feature or system
- Distinct topic not fitting existing notes

**Use templates:**
```markdown
# Note Title

**Created:** 2024-01-15
**Status:** Active | Completed | Archived
**Related:** [[Other-Note]]

## Overview

Brief description of what this note covers.

## Content

Main content here.

## References

- Links to related documentation
- External resources
```

---

### Architectural Decision Records (ADRs)

**For significant technical decisions:**

```markdown
# ADR-001: Use Azure Container Apps for BriefHours

**Date:** 2024-01-15
**Status:** Accepted

## Context

BriefHours needs serverless container hosting with auto-scaling.

## Decision

Use Azure Container Apps instead of AKS or App Service.

## Consequences

**Pros:**
- Simplified deployment
- Auto-scaling built-in
- Lower operational overhead

**Cons:**
- Less control than AKS
- Vendor lock-in to Azure

## Alternatives Considered

- Azure Kubernetes Service (too complex)
- Azure App Service (less container flexibility)
- Self-hosted on homelab (not suitable for production SaaS)
```

---

## Search Best Practices

### Scoped Searches (Preferred)

```bash
# Good - project-specific
Grep "authentication" ~/personal-obsidian/Projects/BriefHours/

# Good - area-specific
Grep "docker" ~/personal-obsidian/Projects/TKN/Infrastructure/

# Avoid - vault-wide (can leak context)
Grep "authentication" ~/personal-obsidian/
```

---

### Multi-Step Searches

For complex queries, use the Task tool with Explore agent:

```
Task: Find all documentation related to Azure deployment across BriefHours notes
Agent: Explore
Scope: ~/personal-obsidian/Projects/BriefHours/
```

---

## Git Operations

**Vault is git-backed and auto-syncs.**

**Manual operations (if needed):**

```bash
# Check status
cd ~/personal-obsidian && git status

# Commit changes
cd ~/personal-obsidian
git add .
git commit -m "docs: update BriefHours architecture notes"
git push

# Pull latest (usually automatic)
cd ~/personal-obsidian && git pull
```

---

## Integration with Claude Memory

**MCP Memory Server** can store and retrieve structured knowledge.

**When to use Obsidian vs Memory:**

| Use Case | Tool | Reason |
|----------|------|--------|
| **User preferences** | Memory | Quick recall, structured queries |
| **Architecture docs** | Obsidian | Long-form, cross-linked documentation |
| **Quick facts** | Memory | Single source of truth, easy updates |
| **Complex decisions** | Obsidian | Context, rationale, alternatives |
| **Session context** | Memory | Auto-loaded at session start |
| **Historical reference** | Obsidian | Git history, long-term archive |

**Session start pattern:**
```typescript
// Load memory context
search_nodes("user")           // Personal preferences
search_nodes("BoroughNexus")   // If in BNX project
search_nodes("BriefHours")     // If in BriefHours project

// Then consult Obsidian for detailed docs as needed
```

---

## Vault Boundaries

### Project Separation

**Important:** Keep project contexts separate to avoid accidental leakage.

**Good:**
- BNX client details → `Projects/BoroughNexus/Clients/`
- BriefHours product → `Projects/BriefHours/`
- Personal experiments → `Projects/TKN/`

**Bad:**
- Mixing BNX client details in BriefHours notes
- Putting work notes in personal Areas

---

### Work vs Personal

**Work (BNX/BriefHours):**
- `Projects/BoroughNexus/`
- `Projects/BriefHours/`

**Personal:**
- `Projects/TKN/`
- `Areas/` (mostly personal)
- `Resources/` (mix of both)

**Shared workspace:** Charlotte has access to relevant BNX notes (if vault is shared).

---

## Common Tasks

### Create Meeting Note

```markdown
# Meeting: Client Name - 2024-01-15

**Attendees:** Simon, Charlotte, Client
**Project:** [[BoroughNexus/Clients/Client-Name]]

## Discussion

- Topic 1
- Topic 2

## Action Items

- [ ] Simon: Task 1
- [ ] Charlotte: Task 2
- [ ] Client: Task 3

## Follow-up

Next meeting: 2024-01-22
```

**Location:** `Projects/BoroughNexus/Clients/ClientName/Meetings/`

---

### Document New Feature

```markdown
# Feature: User Authentication

**Project:** [[BriefHours/Index]]
**Status:** Planning | In Progress | Completed
**Started:** 2024-01-15

## Overview

Add user authentication to BriefHours using Azure AD B2C.

## Requirements

- Email/password login
- Social auth (Google, Microsoft)
- MFA support

## Architecture

- Azure AD B2C for identity
- JWT tokens for session
- Refresh token rotation

## Implementation Notes

- See: `~/.claude/policies/SECURITY.md` for credential handling
- Azure setup: [link to Azure portal]

## Related

- [[BriefHours/Architecture/Security]]
- [[BoroughNexus/AI-Claude/Profile-Setup]]
```

**Location:** `Projects/BriefHours/Features/User-Authentication.md`

---

### Log Incident Resolution

```markdown
# Incident: Database Connection Timeout (2024-01-15)

**Project:** [[BriefHours/Index]]
**Severity:** High
**Duration:** 30 minutes
**Status:** Resolved

## Symptoms

- API returning 500 errors
- Database connection timeouts in logs

## Root Cause

Azure PostgreSQL firewall rule expired.

## Resolution

1. Checked Application Insights logs
2. Identified firewall issue
3. Updated firewall rule via Azure CLI
4. Verified connectivity restored

## Prevention

- Set up monitoring alert for connection failures
- Document firewall rule management in runbook

## Related

- [[BriefHours/Architecture/Database]]
- `~/.claude/operations/RUNBOOK.md`
```

**Location:** `Projects/BriefHours/Incidents/2024-01-15-DB-Timeout.md`
**After 30 days:** Move to `Archive/Projects/BriefHours/Incidents/`

---

## Quick Reference

| Task | Command |
|------|---------|
| **Read note** | `Read ~/personal-obsidian/path/to/note.md` |
| **Search content** | `Grep "term" ~/personal-obsidian/Projects/ProjectName/` |
| **Find notes** | `Glob "**/*.md" ~/personal-obsidian/Projects/ProjectName/` |
| **Edit note** | `Edit ~/personal-obsidian/path/to/note.md` |
| **Create note** | `Write ~/personal-obsidian/path/to/new-note.md` |

---

## References

| Topic | Location |
|-------|----------|
| **Full vault structure** | Load `/obsidian-ref` skill |
| **Memory integration** | Claude MCP Memory Server docs |
| **Project topology** | `~/.claude/architecture/TOPOLOGY.md` |
| **Documentation standards** | This file |
