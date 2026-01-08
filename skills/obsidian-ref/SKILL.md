---
name: obsidian-ref
description: Obsidian vault structure and PARA organization. Load when working with knowledge management.
---

# Obsidian Reference

## Vault Location

```
~/Obsidian/Simon-Personal/
```

## Access Method

Direct file operations - no MCP or REST API needed.

```bash
# Read note
Read ~/Obsidian/Simon-Personal/Projects/BriefHours/Index.md

# Search notes
Grep "search term" ~/Obsidian/Simon-Personal/

# Find notes
Glob "**/*.md" ~/Obsidian/Simon-Personal/Projects/
```

---

## PARA Structure

### Projects/ (Active work with deadlines)

```
Projects/
├── BoroughNexus/           # Parent company
│   ├── AI-Claude/          # Claude tooling docs
│   ├── Infrastructure/     # Infra decisions
│   └── Index.md
├── BriefHours/             # Voice time-tracking product
│   ├── Index.md            # Project overview
│   ├── Backlog.md          # Roadmap and features
│   ├── Architecture.md     # Technical architecture
│   └── Meetings/           # Meeting notes
└── [other active projects]
```

### Areas/ (Ongoing responsibilities)

```
Areas/
├── Personal/               # Charlotte, Social, Tax (encrypted)
├── Hobbies/                # Comedy Course
├── Life/                   # Travel SOPs, Scuba
└── Health/                 # Medical, fitness
```

### Resources/ (Reference material)

```
Resources/
├── DnD/                    # D&D 5e SRD
├── Oxford MSc/             # Cybersecurity course notes
├── Recipes/                # Cooking
└── Tech/                   # Technical references
```

### Archive/ (Inactive items)

Completed projects and outdated resources.

### attachments/

Images, PDFs, and other media referenced by notes.

---

## Key Files

| File | Purpose |
|------|---------|
| `Projects/BriefHours/Index.md` | BriefHours project overview |
| `Projects/BriefHours/Backlog.md` | Feature roadmap |
| `Projects/BoroughNexus/AI-Claude/` | Claude integration docs |

---

## Encryption

Sensitive content in `Areas/Personal/` uses **Meld Encrypt** plugin.

- Content between `%%` markers is encrypted
- Requires passphrase to decrypt in Obsidian app
- Claude cannot read encrypted content

---

## Sync

- **Obsidian Sync** (paid) syncs across iOS/Mac/Windows
- Changes made via Claude are synced automatically
- No conflict resolution needed for direct file edits

---

## Plugins

| Plugin | Purpose |
|--------|---------|
| Meld Encrypt | Encrypt sensitive sections |
| Todoist Sync | Sync tasks with Todoist |
| Dataview | Query notes as database |

---

## Common Operations

### Create new project note

```bash
Write ~/Obsidian/Simon-Personal/Projects/NewProject/Index.md
```

### Find all notes mentioning topic

```bash
Grep "BriefHours" ~/Obsidian/Simon-Personal/ --type md
```

### List recent notes

```bash
Glob "**/*.md" ~/Obsidian/Simon-Personal/Projects/ | head -20
```

---

## Basalt TUI

Terminal interface for Obsidian (optional).

```bash
basalt                      # Launch TUI
~/.cargo/bin/basalt         # Binary location
```

---

## Linking Convention

- Use `[[WikiLinks]]` for internal links
- Use relative paths for attachments: `![[attachments/image.png]]`
- Tags: `#project`, `#area`, `#resource`
