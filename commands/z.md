# Zero-Friction Commit Command

> **Description:** Automatically commit, push, and document recent work

**Invoke:** bun run ~/.claude/scripts/z/index.ts

## Usage

```bash
/z                  # Auto-commit, push, and create summary
/z "custom message" # Commit with custom message
```

## What It Does

1. **Analyzes changes** - Examines git diff and status
2. **Generates summary** - Creates meaningful commit message based on files changed
3. **Commits changes** - Stages and commits with generated message + signature
4. **Pushes to remote** - Automatically pushes to current branch
5. **Documents work** - Creates/updates plan file with summary (optional)

## Examples

```bash
/z
# Automatically analyzes changes and creates semantic commit

/z "Implement user authentication system"
# Uses your message with auto-generated details about what changed
```

## Features

- 🔍 **Smart analysis** - Reads git diff to understand what changed
- 📝 **Auto-generated messages** - Creates meaningful summaries from file patterns
- 🚀 **One-step workflow** - Commit → Push → Document in one command
- 🔐 **Signature added** - Includes "Generated with Claude Code" footer
- ✅ **Safety checks** - Won't commit if no changes exist
- 📋 **Documentation** - Optional plan file creation/update

## Best Used For

- ✅ Quick iteration cycles
- ✅ Automating tedious git workflow
- ✅ Keeping commits organized
- ✅ Batch operations with documentation

## Output

```
📊 Analyzing changes...
✅ Changes detected: 5 files modified

Generated commit message:
---
Implement feature X with tests and documentation

- Add feature implementation in src/
- Add comprehensive tests
- Update README with usage examples

🤖 Generated with Claude Code
---

[commits]
[pushes]
📚 Summary documented in plans/work-summary.md
```
