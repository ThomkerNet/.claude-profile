# Claude Code Profile

A portable, self-contained Claude Code configuration that works on Windows, macOS, and Linux.

**NEW:** Version 2.0 uses a two-phase architecture that separates version-controlled configuration from Claude's runtime directory. See [MIGRATION.md](MIGRATION.md) if upgrading from v1.0.

## Features

- **MCP Servers** - Pre-configured Context7, Puppeteer, Sequential Thinking, Memory, plus TKN homelab servers via Tailscale
- **Slash Commands** - `/cname`, `/z`, `/zcicd`, `/zdoc`
- **Status Line** - Cross-platform status bar with model, directory, git branch, and custom labels
- **Portable** - Clone once, sync everywhere. Config stays in sync via git, runtime data stays local.

## Architecture

This profile uses a **two-phase setup** to avoid conflicts with Claude's initialization:

| Location | Purpose | Content |
|----------|---------|---------|
| `~/.claude-profile/` | Version-controlled config repo | Commands, hooks, skills, templates |
| `~/.claude/` | Active Claude profile (runtime) | Credentials, history, symlinks to config |

**Why?** Claude expects to create `~/.claude` during first login. By keeping config in a separate location, we avoid backup/restore issues and cleanly separate config from runtime data.

## Quick Install

### macOS / Linux
```bash
# Clone to staging location (NOT ~/.claude)
git clone https://github.com/ThomkerNet/.claude-profile.git ~/.claude-profile

# Run bootstrap (handles login + config install)
cd ~/.claude-profile
./bootstrap.sh
```

### Windows (PowerShell)
```powershell
# Clone to staging location
git clone https://github.com/ThomkerNet/.claude-profile.git $HOME\.claude-profile

# Run bootstrap
cd $HOME\.claude-profile
.\install.ps1
```

**Note:** The repository should be cloned as `.claude-profile` (not `.claude`). If the GitHub repo is still named `.claude`, it should be renamed to `.claude-profile` to match the new convention.

## What Gets Installed

### In `~/.claude-profile/` (Repo)
| Component | Description |
|-----------|-------------|
| `bootstrap.sh` | First-time setup script |
| `setup.sh` | Core installation script (called by bootstrap) |
| `sync.sh` | Quick update script |
| `commands/` | Slash commands |
| `hooks/` | PostToolUse, UserPromptSubmit, Stop hooks |
| `skills/` | On-demand reference skills |
| `agents/` | Custom agents |
| `statuslines/` | Cross-platform status line scripts |
| `tools/` | Utility scripts (Bitwarden, Vaultwarden, etc.) |
| `settings.template.json` | Template for settings (paths filled in at install) |
| `mcp-servers.json` | MCP server definitions |

### In `~/.claude/` (Active Profile)
| Component | Description |
|-----------|-------------|
| `.credentials.json` | Claude auth credentials (created by login) |
| `history.jsonl` | Session history (runtime) |
| `settings.json` | Generated from template |
| `CLAUDE.md` | Copy of global instructions |
| `commands/` | **Symlink** → `~/.claude-profile/commands/` |
| `hooks/` | **Symlink** → `~/.claude-profile/hooks/` |
| `skills/` | **Symlink** → `~/.claude-profile/skills/` |
| `agents/` | **Symlink** → `~/.claude-profile/agents/` |
| `statuslines/` | **Symlink** → `~/.claude-profile/statuslines/` |
| `tools/` | **Symlink** → `~/.claude-profile/tools/` |
| `plans/`, `todos/`, `projects/` | Runtime data (local only) |

## Post-Install Setup

### 1. tmux Configuration (macOS/Linux)

The setup script automatically:
- Installs tmux (via Homebrew on macOS, package manager on Linux)
- Copies your tmux configuration to `~/.tmux.conf`
- Backs up any existing config with a timestamp

Your current tmux settings are preserved in `~/.claude/tmux.conf` and can be updated there.

#### macOS Clipboard Integration

On macOS, tmux is configured to integrate with the system clipboard:

| Key Binding | Action |
|-------------|--------|
| `Prefix + y` | Copy selection to macOS clipboard and exit copy mode |
| `Prefix + Y` | Copy selection to macOS clipboard and stay in copy mode |
| `Prefix + ]` | Paste from macOS clipboard |

Uses `pbcopy` and `pbpaste` for seamless integration with macOS system clipboard. This is only applied on macOS.

### 2. Environment Variables

Set these for full functionality:

| Variable | Purpose |
|----------|---------|
| `FIRECRAWL_API_KEY` | Firecrawl MCP server |

### 3. Verify MCP Servers

```bash
claude mcp list
```

## Usage

### Slash Commands

| Command | Description |
|---------|-------------|
| `/cname <label>` | Set a custom session label in the status bar |
| `/z [message]` | Zero-friction commit, push, and document |
| `/zcicd [message]` | Zero-friction commit with CI/CD monitoring |
| `/zdoc [message]` | Zero-friction commit with Obsidian documentation |

### Status Line

The status line shows:
- Current model (Opus, Sonnet, Haiku)
- Current directory
- Git branch (if in a repo)
- Custom session label (set via `/cname`)
- Token usage and context percentage
- Session cost and lines changed

#### Platform-Specific Setup

**Windows (PowerShell)**
- Uses `statusline.ps1` automatically
- Requires PowerShell 5.0+
- Installed and configured by `install.ps1`

**macOS/Linux (Bash/Zsh)**
- Uses `statusline.sh` automatically
- Requires: `jq` and `bc` (both standard on macOS, installed by setup.sh)
- Installed and configured by `setup.sh`
- Compatible with bash, zsh, and other POSIX shells

#### Customizing Your Session Label

Use `/cname` to set a custom label for the current session:
```
/cname Homelab
/cname Project-X
/cname Feature-Development
```

The custom label appears in the status line and is stored in `~/.claude/.session-label`

### Zero-Friction Commit (`/z`)

Automate the entire commit → push → document workflow in one command.

#### What It Does

1. **Analyzes changes** - Examines git diff to understand what changed
2. **Generates commit message** - Creates semantic message based on file patterns
3. **Stages and commits** - Automatically commits all changes
4. **Pushes to remote** - Pushes to current branch
5. **Documents work** - Creates/appends to work summary plan

#### Usage

```bash
/z                           # Auto-analyze and commit
/z "Implement user auth"     # Commit with custom message
```

## File Structure

### Repository (`~/.claude-profile/`)
```
~/.claude-profile/          # Git repo (version controlled)
├── bootstrap.sh            # First-time setup
├── setup.sh                # Core installation
├── sync.sh                 # Quick update script
├── CLAUDE.md               # Global instructions
├── settings.template.json  # Settings template
├── mcp-servers.json        # MCP servers to install
├── commands/               # Slash commands
│   ├── cname.md
│   ├── z.md
│   └── zcicd.md
├── hooks/
│   └── memory/             # Memory hooks
├── skills/
│   └── ultrathink/         # Extended reasoning skill
├── agents/                 # Custom agents
├── statuslines/
│   ├── statusline.ps1      # PowerShell (Windows)
│   └── statusline.sh       # Bash/Zsh (macOS/Linux)
└── tools/                  # Utility scripts
```

### Active Profile (`~/.claude/`)
```
~/.claude/                  # Active Claude profile (runtime)
├── .credentials.json       # Auth (created by login, gitignored)
├── history.jsonl           # Session history (runtime)
├── settings.json           # Generated from template
├── CLAUDE.md               # Copy from repo
├── commands/  →            # Symlink to ~/.claude-profile/commands/
├── hooks/     →            # Symlink to ~/.claude-profile/hooks/
├── skills/    →            # Symlink to ~/.claude-profile/skills/
├── agents/    →            # Symlink to ~/.claude-profile/agents/
├── statuslines/ →          # Symlink to ~/.claude-profile/statuslines/
├── tools/     →            # Symlink to ~/.claude-profile/tools/
├── plans/                  # User plans (runtime, local only)
├── todos/                  # User todos (runtime, local only)
└── projects/               # Project state (runtime, local only)
```

## Making Changes to Your Profile

### Where to Launch Claude
**Launch Claude from anywhere** - it always uses `~/.claude` as the active profile.

### Editing Config Files
1. **Edit files in `~/.claude-profile/`** (the git repo)
   - Commands: `~/.claude-profile/commands/`
   - Skills: `~/.claude-profile/skills/`
   - Hooks: `~/.claude-profile/hooks/`
   - MCP servers: `~/.claude-profile/mcp-servers.json`
   - Settings template: `~/.claude-profile/settings.template.json`

2. **Changes are immediate** for symlinked directories
   - Adding/editing skills: Works immediately (symlinked)
   - Adding/editing commands: Works immediately (symlinked)
   - Adding/editing hooks: Works immediately (symlinked)

3. **Run sync for template changes**
   ```bash
   cd ~/.claude-profile
   ./sync.sh
   ```
   Required for:
   - Changes to `settings.template.json`
   - Changes to `mcp-servers.json`
   - Changes to `CLAUDE.md`

### Meta-Editing: Claude Modifying Its Own Profile

**Claude can edit its own profile!** Since config lives in `~/.claude-profile/` (a git repo), you can ask Claude to:

```
Add a new skill to ~/.claude-profile/skills/
Modify MCP server config in ~/.claude-profile/mcp-servers.json
```

**Workflow:**
1. Ask Claude to edit files in `~/.claude-profile/`
2. Changes to symlinked dirs (commands, skills, hooks) work immediately
3. For template changes, ask Claude to run `./sync.sh`
4. Commit and push from `~/.claude-profile/`

**Safety:** Runtime data (`~/.claude/` credentials, history, plans) is never modified during meta-editing.

### Updating from Git

After pulling updates from the remote repo:

```bash
cd ~/.claude-profile
git pull
./sync.sh
```

This will:
- Update symlinks
- Regenerate `settings.json` from template
- Update `CLAUDE.md`
- Reinstall hook dependencies if needed

### Full Reinstall
If something breaks or you need to reinstall MCP servers:

```bash
cd ~/.claude-profile
./setup.sh
```

## Troubleshooting

### MCP servers not connecting
```bash
claude mcp list  # Check status
claude mcp remove <name> && claude mcp add ...  # Reinstall
```

### Settings not applying
Restart Claude Code after running install script.

## License

MIT
