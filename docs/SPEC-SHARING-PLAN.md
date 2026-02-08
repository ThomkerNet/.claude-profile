# Multi-Agent Spec Sharing System

## Overview

Enable multiple Claude agents on the same machine to share work specifications via `*-SPEC.md` files. When an agent detects a new spec file, it prompts the user to process it through a structured workflow.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Agent A        │     │  Agent B        │     │  Agent C        │
│  (Project X)    │     │  (Project Y)    │     │  (Project Z)    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │  Writes SPEC.md       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Shared Spec Directory                        │
│              ~/.claude/specs/ or project/.claude-specs/          │
│                                                                  │
│  ├── project-x-feature-SPEC.md                                  │
│  ├── project-y-refactor-SPEC.md                                 │
│  └── .processed/  (completed specs moved here)                  │
└─────────────────────────────────────────────────────────────────┘
         │
         │  fswatch / launchd / systemd
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Spec Watcher Daemon                           │
│                                                                  │
│  - Watches for new *-SPEC.md files                              │
│  - Detects which project directory each belongs to              │
│  - Records pending specs in ~/.claude/.pending-specs.json       │
└─────────────────────────────────────────────────────────────────┘
         │
         │  User runs /process-spec
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Spec Processor Skill                          │
│                                                                  │
│  1. List pending specs, let user select                         │
│  2. Read and summarize the spec                                 │
│  3. Create detailed implementation plan                         │
│  4. AI peer review (via tkn-aipeerreview MCP server)             │
│  5. Present summary and ask for approval                        │
│  6. Mark spec as processed                                      │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Spec File Format

Standard markdown format with YAML frontmatter:

```markdown
---
title: Feature X Implementation
from: agent-a
to: agent-b  # optional, can be "any"
priority: high
created: 2025-01-06T12:00:00Z
project: ~/git/project-y
---

# Feature X Specification

## Summary
Brief description of what needs to be implemented.

## Requirements
- Requirement 1
- Requirement 2

## Context
Background information, related files, dependencies.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Notes
Additional context from the originating agent.
```

### 2. Spec Watcher Daemon

**Location:** `~/.claude/services/spec-watcher.sh`

**Functionality:**
- Watches `~/.claude/specs/` and project directories for new `*-SPEC.md` files
- On new file detection:
  - Validates format (has frontmatter, required fields)
  - Records in `~/.claude/.pending-specs.json`
- Runs via launchd (macOS) / systemd (Linux)

**launchd plist:** `com.claude.spec-watcher.plist`
- StartInterval: 60 seconds (check every minute)
- Or use FSEvents for real-time detection

### 3. Pending Specs Registry

**Location:** `~/.claude/.pending-specs.json`

```json
{
  "specs": [
    {
      "id": "abc123",
      "file": "~/.claude/specs/feature-x-SPEC.md",
      "title": "Feature X Implementation",
      "from": "agent-a",
      "to": "agent-b",
      "project": "~/git/project-y",
      "detected": "2025-01-06T12:00:00Z",
      "status": "pending"
    }
  ]
}
```

### 4. `/process-spec` Skill

**Location:** `~/.claude/skills/process-spec/SKILL.md`

**Workflow:**
1. **List pending specs** - Show available specs with summary
2. **User selects** - Pick which spec to process
3. **Read & summarize** - Parse spec, extract requirements
4. **Create implementation plan** - Detailed step-by-step plan
5. **AI peer review** - Use `tkn-aipeerreview` MCP server tools for multi-model review
6. **Present to user** - Summary + plan + review feedback
7. **Get approval** - User confirms or requests changes
8. **Mark processed** - Move to `.processed/` directory

### 5. Idle Detection (Optional Enhancement)

**Challenge:** Claude Code doesn't have native idle detection hooks.

**Solutions:**
1. **Statusline-based detection:**
   - Statusline tracks last interaction time
   - After 5 min idle, statusline shows "Pending specs: 2"
   - User sees visual indicator

2. **Auto-prompt hook:**
   - Hook checks for pending specs on each user prompt
   - If specs exist, adds reminder to response

## Implementation Steps

### Phase 1: Core Infrastructure
1. Create spec file format documentation
2. Create `~/.claude/specs/` directory structure
3. Implement spec watcher daemon (bash + fswatch or pure polling)
4. Create launchd/systemd service files
5. Add to setup.sh installation

### Phase 2: Notification & Registry
1. Implement pending specs JSON registry
2. Update statusline to show pending spec count

### Phase 3: Processing Skill
1. Create `/process-spec` skill
2. Implement spec parsing (YAML frontmatter + markdown)
3. Implement implementation plan generation
4. Integrate AI peer review (via `tkn-aipeerreview` MCP server tools)
5. Add approval workflow

### Phase 4: Polish & Integration
1. Add `/create-spec` skill for generating specs
2. Add spec templates for common patterns
3. Add spec history/archive
4. Documentation

## File Structure

```
~/.claude/
├── specs/
│   ├── incoming/          # New specs land here
│   ├── processing/        # Currently being worked on
│   └── completed/         # Archived after completion
├── services/
│   ├── spec-watcher.sh
│   └── com.claude.spec-watcher.plist
├── skills/
│   ├── process-spec/
│   │   └── SKILL.md
│   └── create-spec/
│       └── SKILL.md
└── .pending-specs.json
```

## Security Considerations

1. **Spec validation** - Only process files matching expected format
2. **Path sanitization** - Prevent path traversal in project paths
3. **Rate limiting** - Don't spam notifications
4. **File permissions** - Specs directory should be user-only (700)

## Questions for User

1. Should specs be in a central `~/.claude/specs/` or per-project `.claude-specs/`?
2. Should idle detection auto-prompt, or just show indicator?
3. Should processed specs be archived or deleted?
4. Which review type should be used via `tkn-aipeerreview` MCP server?
