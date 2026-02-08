# Migration Guide: v1.0 → v2.0

This guide helps you migrate from the old single-directory setup to the new two-phase architecture.

## What Changed?

### v1.0 (Old Approach)
- Repo cloned directly to `~/.claude`
- Claude's login process backed up the repo → `.claude.backup.TIMESTAMP`
- Config and runtime files mixed together
- Difficult to sync across machines

### v2.0 (New Approach)
- Repo cloned to `~/.claude-profile` (staging)
- Active profile stays in `~/.claude` (runtime)
- Config files symlinked from repo to active profile
- Clean separation: config (version controlled) vs runtime (local only)

## Why Migrate?

- **No more backup conflicts** - Claude creates `~/.claude` first, then config is installed
- **Clean sync** - `git pull && ./sync.sh` updates config without touching runtime data
- **Portable** - Clone once on new machine, run bootstrap, done
- **No credential leaks** - Runtime files never mixed with git repo

## Migration Steps

### Step 1: Backup Your Current Setup

```bash
# Backup current active profile
cp -r ~/.claude ~/.claude.backup.migration

# Backup credentials (important!)
cp ~/.claude/.credentials.json ~/claude-credentials.backup.json

# If you have important runtime data, back it up too
cp -r ~/.claude/plans ~/plans.backup
cp -r ~/.claude/todos ~/todos.backup
cp -r ~/.claude/projects ~/projects.backup
```

### Step 2: Clone Repo to New Location

```bash
# Clone to the new staging location
# NOTE: Change URL to .claude-profile if repo was renamed
git clone https://github.com/ThomkerNet/.claude-profile.git ~/.claude-profile

# Or if you already have a backup folder with the repo:
mv ~/.claude.backup.1767693620 ~/.claude-profile
```

### Step 3: Remove Old Active Profile

**IMPORTANT:** Make sure you backed up credentials in Step 1!

```bash
# Remove the old ~/.claude directory
# (Claude will recreate it on next login)
rm -rf ~/.claude
```

### Step 4: Run Bootstrap

The bootstrap script will:
1. Ensure Claude CLI is installed
2. Prompt you to login (creates fresh `~/.claude`)
3. Install config from `~/.claude-profile`

```bash
cd ~/.claude-profile
./bootstrap.sh
```

Follow the prompts. When asked to login to Claude, complete the authentication.

### Step 5: Restore Runtime Data

After bootstrap completes, restore your backed-up runtime files:

```bash
# Restore plans, todos, projects
cp -r ~/plans.backup ~/.claude/plans
cp -r ~/todos.backup ~/.claude/todos
cp -r ~/projects.backup ~/.claude/projects

# Restore history if you want it
cp ~/.claude.backup.migration/history.jsonl ~/.claude/history.jsonl
```

### Step 6: Verify Installation

```bash
# Check that symlinks are correct
ls -la ~/.claude/

# Should see symlinks like:
# commands -> /Users/you/.claude-profile/commands
# hooks -> /Users/you/.claude-profile/hooks
# skills -> /Users/you/.claude-profile/skills
# etc.

# Verify Claude works
claude

# Check MCP servers
claude mcp list
```

### Step 7: Clean Up Backups

Once everything works:

```bash
# Remove backup files
rm -rf ~/.claude.backup.migration
rm ~/claude-credentials.backup.json
rm -rf ~/plans.backup ~/todos.backup ~/projects.backup

# Remove old backup folders if any
rm -rf ~/.claude.backup.*
rm -rf ~/.claude.fresh
```

## What About My Customizations?

### Custom Skills, Commands, Hooks
These are now in `~/.claude-profile/` and symlinked to `~/.claude/`. Edit them in the repo:

```bash
# Edit a skill
cd ~/.claude-profile/skills/my-skill
# Make changes...

# Changes are immediately visible to Claude (symlinked)
# No sync needed for symlinked directories
```

### Custom Settings
Settings are generated from `~/.claude-profile/settings.template.json`:

```bash
# Edit the template
vim ~/.claude-profile/settings.template.json

# Regenerate settings.json
cd ~/.claude-profile
./sync.sh
```

### MCP Servers
MCP server definitions are in `~/.claude-profile/mcp-servers.json`:

```bash
# Edit MCP servers
vim ~/.claude-profile/mcp-servers.json

# Reinstall MCP servers
cd ~/.claude-profile
./setup.sh  # This will reinstall all MCP servers
```

### Secrets
Secrets should be in `~/.claude-profile/secrets.json` (gitignored):

```bash
# If you had secrets in the old setup, copy them
cp ~/.claude.backup.migration/secrets.json ~/.claude-profile/secrets.json

# Reapply secrets
cd ~/.claude-profile
./setup.sh
```

## Workflow Changes

### Old Workflow (v1.0)
```bash
cd ~/.claude
# Make changes...
git add .
git commit -m "Update"
git push
```

### New Workflow (v2.0)
```bash
# Edit config files
cd ~/.claude-profile
vim commands/my-command.md  # Changes visible immediately

# For template changes, regenerate
./sync.sh

# Commit and push
git add .
git commit -m "Update"
git push
```

### On Another Machine
```bash
# Old way: Pull and re-run setup
cd ~/.claude
git pull
./setup.sh

# New way: Pull and sync
cd ~/.claude-profile
git pull
./sync.sh
```

## Troubleshooting

### "Claude is not logged in" error during bootstrap
The bootstrap script checks for `~/.claude/.credentials.json`. If you see this error:
1. Run `claude` manually to login
2. Complete authentication
3. Re-run `./bootstrap.sh`

### Symlinks point to wrong location
If symlinks point to the old location:
```bash
cd ~/.claude-profile
./sync.sh  # This will fix symlinks
```

### MCP servers not working after migration
Reinstall MCP servers:
```bash
cd ~/.claude-profile
./setup.sh
```

### Lost credentials
If you didn't back up `.credentials.json`, you'll need to login again:
```bash
claude
# Complete login flow
```

### Old backup folders cluttering home directory
Remove them:
```bash
ls -d ~/.claude.backup.* ~/.claude.fresh
# Review the list, then:
rm -rf ~/.claude.backup.* ~/.claude.fresh
```

## FAQ

### Do I need to rename the GitHub repo?
**Recommended.** Rename `ThomkerNet/.claude-profile` → `ThomkerNet/.claude-profile-profile` to match the new convention. Update your clone:

```bash
cd ~/.claude-profile
git remote set-url origin https://github.com/ThomkerNet/.claude-profile-profile.git
```

### Will this affect my existing Claude sessions?
No. Claude sessions are separate from the profile directory structure. You may need to restart Claude after migration.

### Can I keep both old and new setups?
Not recommended. The old setup (`~/.claude` as a git repo) conflicts with Claude's expected directory structure. Migrate to v2.0 for best results.

### What if I want to go back to v1.0?
You can, but you'll face the original issues (backup folders, mixed runtime/config files). If you must revert:

1. Remove `~/.claude` (back up runtime data first!)
2. Clone repo directly to `~/.claude`
3. Run old `setup.sh`

But this defeats the purpose of the two-phase architecture.

## Need Help?

If you run into issues during migration:
1. Check your backups are complete (credentials, plans, todos)
2. Review the troubleshooting section above
3. Open an issue: https://github.com/ThomkerNet/.claude-profile-profile/issues

## Summary

| Task | v1.0 (Old) | v2.0 (New) |
|------|------------|------------|
| **Clone** | `~/.claude` | `~/.claude-profile` |
| **Setup** | `./setup.sh` | `./bootstrap.sh` |
| **Edit Config** | In `~/.claude` (mixed with runtime) | In `~/.claude-profile` (clean separation) |
| **Update** | `git pull && ./setup.sh` | `git pull && ./sync.sh` |
| **Runtime Data** | Mixed with config | Separate in `~/.claude` |
| **Credentials** | Mixed with git repo | Only in `~/.claude` (never in git) |
