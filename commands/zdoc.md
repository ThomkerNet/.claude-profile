# Zero-Friction Commit with Documentation

> **Description:** Commit, push, and document work in both Claude plans and Obsidian vault

## Usage

```bash
/zdoc                  # Auto-commit with Obsidian documentation
/zdoc "custom message" # Commit with custom message + Obsidian docs
```

## What It Does

1. **Run /z** - Execute the standard zero-friction commit (stage, commit, push)
2. **Analyze context** - Review what was changed and why
3. **Explore Obsidian** - Search the vault to find the most appropriate location
4. **Update Obsidian** - Add relevant notes intelligently

## Execution Steps

### Step 1: Load Context

```
Load /obsidian-ref to get vault path and PARA structure
```

### Step 2: Commit Changes

Execute the `/z` command to stage, commit, and push all changes.

### Step 3: Analyze What Changed

Review the committed changes to understand:
- What systems/components were modified
- What architectural decisions were made
- What new capabilities were added
- What technical knowledge is worth preserving

### Step 4: Explore Obsidian Vault

**Before writing, explore the vault to find the best location:**

```bash
# Search for existing related notes
Grep "<relevant keywords>" <vault_path>/

# List existing project structure
Glob "**/*.md" <vault_path>/Projects/

# Check for existing notes on this topic
Grep "<component name>" <vault_path>/Projects/
```

**Location selection priority:**
1. **Existing note** - If a relevant note already exists, append to it
2. **Existing project folder** - If the project has a folder, create a note there
3. **Related area** - Match to Resources/ or Areas/ if appropriate
4. **Create new** - Only create new structure if nothing exists

### Step 5: Write Documentation

**What to document:**
- Architecture decisions and rationale
- New features or capabilities
- Configuration changes affecting behavior
- API changes or integrations
- Security-related changes
- Technical gotchas and edge cases
- System interactions worth remembering

**Skip documenting:**
- Minor bug fixes, typos, formatting
- Routine dependency updates
- Changes already well-documented in code

**Note format:**

```markdown
## YYYY-MM-DD - [Brief Description]

**Context:** Why this change was made

**Changes:**
- What was added/modified/removed

**Technical Notes:**
- Implementation details worth remembering
- Gotchas or edge cases discovered
- Dependencies or requirements

**Related:** [[Link to related notes]]
```

**Use WikiLinks** (`[[Note Name]]`) to connect related concepts.

## Examples

### Example 1: Claude Profile Update

Changes to `~/.claude-profile/` scripts:
1. Search vault for "Claude" or "AI" notes
2. Find `Projects/BoroughNexus/AI-Claude/`
3. Append to existing note or create topic-specific note

### Example 2: New Integration

Adding a new MCP server:
1. Search for existing MCP or integration docs
2. Update architecture notes with new capability
3. Link to related infrastructure notes

### Example 3: Infrastructure Change

Docker/homelab configuration:
1. Search for TKNet or homelab notes
2. Update relevant infrastructure documentation
3. Note any operational considerations

## Output

```
📊 Analyzing changes...
✅ Committed and pushed: "Add AI peer review model updates"

🔍 Exploring Obsidian vault...
   Found related: Projects/BoroughNexus/AI-Claude/Tools.md

📝 Obsidian Documentation:
   → Updated Projects/BoroughNexus/AI-Claude/Tools.md
   → Added: Model selection rationale for peer review
   → Linked: [[LiteLLM]], [[GitHub Copilot]]

✨ Done! Changes committed, pushed, and documented.
```
