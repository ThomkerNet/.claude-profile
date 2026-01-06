# Claude Code Profile

A portable, self-contained Claude Code configuration that works on Windows, macOS, and Linux.

**NEW:** Version 2.0 uses a two-phase architecture that separates version-controlled configuration from Claude's runtime directory. See [MIGRATION.md](MIGRATION.md) if upgrading from v1.0.

## Features

- **Telegram Integration** - Remote control Claude via Telegram with two-way communication
- **MCP Servers** - Pre-configured Context7, Puppeteer, Firecrawl, Sequential Thinking
- **Gemini Second Opinions** - Get alternative perspectives via Gemini CLI
- **Custom Skills** - Solution review skill for comprehensive code audits
- **Slash Commands** - `/telegram`, `/telegram-end`, `/review`, `/cname`
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
git clone https://github.com/ample-engineer/.claude-profile.git ~/.claude-profile

# Run bootstrap (handles login + config install)
cd ~/.claude-profile
./bootstrap.sh
```

### Windows (PowerShell)
```powershell
# Clone to staging location
git clone https://github.com/ample-engineer/.claude-profile.git $HOME\.claude-profile

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
| `commands/` | Slash commands for Telegram integration |
| `hooks/` | PostToolUse, UserPromptSubmit, Stop hooks |
| `skills/` | Solution review skill |
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

### 1. Telegram Integration (Optional)

```bash
# 1. Create bot via @BotFather on Telegram
# 2. Get chat ID from https://api.telegram.org/bot<TOKEN>/getUpdates
# 3. Configure:
bun run ~/.claude/hooks/telegram-bun/index.ts config <BOT_TOKEN> <CHAT_ID>

# 4. In Claude, run:
/telegram
```

### 2. tmux Configuration (macOS/Linux)

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

### 3. Environment Variables

Set these for full functionality:

| Variable | Purpose |
|----------|---------|
| `FIRECRAWL_API_KEY` | Firecrawl MCP server |
| `GEMINI_API_KEY` | Gemini CLI for second opinions |

### 4. Verify MCP Servers

```bash
claude mcp list
```

## Usage

### Slash Commands

| Command | Description |
|---------|-------------|
| `/telegram` | Start Telegram integration |
| `/telegram-end` | End Telegram integration |
| `/cname <label>` | Set a custom session label in the status bar |
| `/aipeerreview [file]` | Multi-model AI peer review of plans/issues |
| `/z [message]` | Zero-friction commit, push, and document |

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

### AI Peer Review (`/aipeerreview`)

Get comprehensive peer reviews of your plans and issues using multiple AI models simultaneously.

#### What It Does

Sends your most recent plan or issue file to **three AI models in parallel** for comprehensive vetting:
- **ChatGPT (gpt-5.1)** - Advanced reasoning and practical insights
- **Gemini Pro (gemini-3-pro-preview)** - Multi-modal understanding and novel perspectives
- **Claude Opus (claude-opus-4.5)** - Comprehensive analysis and edge case detection

#### Usage

```bash
/aipeerreview                         # Review most recent plan
/aipeerreview plans/my-feature.md    # Review specific file
```

#### Features

- **Parallel execution** - All 3 models run simultaneously (~3x faster than sequential)
- **Automatic discovery** - Finds most recent plan in `~/.claude/plans/` or items in `queue.md`
- **Structured reviews** - Each model provides:
  - Strengths and what works well
  - Weaknesses, pitfalls, and edge cases
  - Feasibility concerns
  - Security implications
  - Actionable recommendations

- **Consensus detection** - See what all models agree on vs. divergent opinions
- **Handles complex documents** - 10MB+ buffer for large plans

#### Example Output

```
🔍🔍🔍 AI PEER REVIEW - Multi-Model Analysis 🔍🔍🔍

Document: my-feature-plan.md
Models: ChatGPT, Gemini Pro, Claude Opus

⚡ Starting parallel peer review across 3 AI models...

======================================================================
📋 Review by ChatGPT
======================================================================
[Strengths and weaknesses analysis...]

======================================================================
📋 Review by Gemini Pro
======================================================================
[Alternative perspective with novel insights...]

======================================================================
📋 Review by Claude Opus
======================================================================
[Comprehensive analysis with security and feasibility assessment...]

✅ Peer review complete! (87.3s)
```

#### When to Use

- ✅ Before implementing major features
- ✅ Validating architecture decisions
- ✅ Security and feasibility review
- ✅ Getting diverse perspectives on approach
- ✅ Catching edge cases and pitfalls

#### Tips

- **Small plans execute faster** - Keep plans focused and concise
- **Run in background** - Parallel execution means all 3 models work simultaneously (~30s for all 3)
- **Custom labels** - Use `/cname "feature-name"` to label the session for easy reference
- **Archive good reviews** - Save particularly insightful reviews to a `reviews/` folder

#### Implementation Notes

The `/aipeerreview` command uses the **Copilot CLI** to invoke multiple models in parallel:

- **Async parallelization** - Uses `Promise.all()` with async `exec` for true non-blocking I/O
- **Secure temp files** - Creates atomic temp directories with restrictive permissions (0o600)
- **Guaranteed cleanup** - Try/finally blocks ensure temp files deleted even on errors
- **Cross-platform** - Uses `os.tmpdir()` and `path.join()` for Windows/macOS/Linux compatibility
- **Timeout protection** - 5-minute timeout prevents hung processes
- **Model validation** - Allowlist check prevents injection attacks

The feature was stress-tested using itself (meta peer review!) which identified and led to fixes for:
- True async parallelization (not sequential blocking calls)
- Reliable cleanup on all code paths
- Windows path compatibility

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

#### Features

- **Smart categorization** - Groups changes by type (features, tests, docs, config)
- **Semantic messages** - Auto-generates meaningful commit messages
- **One-step workflow** - Combines git workflow into single command
- **Automatic documentation** - Logs work in `plans/work-summary.md`
- **Safety checks** - Fails if no changes exist
- **Custom messages** - Optionally override generated message

#### Example

```
📊 Analyzing changes...
✅ Changes detected: 5 file(s)

Generated commit message:
---
Add AI peer review feature with fixes and documentation

- Add/update: skills/aipeerreview/index.ts
- Tests: skills/aipeerreview/test.ts
- Documentation: README.md, plans/aipeerreview-feature.md
---

✅ Changes staged
✅ Committed
✅ Pushed to remote
📚 Work documented in work-summary.md

✨ Done! Changes committed, pushed, and documented.
```

#### Workflow Benefits

- **Faster iteration** - No manual commit/push/document steps
- **Consistent commits** - Semantic messages across team
- **Automatic logging** - Work history in version control
- **Reduced context switching** - Stay in your workflow

### Telegram Commands

In Telegram:
| Command | Description |
|---------|-------------|
| `/status` | List active Claude sessions |
| `/tell do X` | Send instruction to Claude |
| `! do X` | Shorthand for /tell |
| `/ping` | Check if listener is alive |
| `/help` | Show all commands |

### Skills

| Skill | Trigger |
|-------|---------|
| `/review` | Comprehensive solution review with Gemini |

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
│   ├── telegram.md
│   ├── telegram-end.md
│   ├── cname.md
│   └── review.md
├── hooks/
│   └── telegram-bun/       # Telegram integration
├── skills/
│   └── solution-review/    # Code review skill
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
Update the Telegram command in ~/.claude-profile/commands/telegram.md
Modify MCP server config in ~/.claude-profile/mcp-servers.json
```

**Workflow:**
1. Ask Claude to edit files in `~/.claude-profile/`
2. Changes to symlinked dirs (commands, skills, hooks) work immediately
3. For template changes, ask Claude to run `./sync.sh`
4. Commit and push from `~/.claude-profile/`

**Example:**
```
User: "Add a new /status command that shows current git branch and model"

Claude will:
1. Create ~/.claude-profile/commands/status.md
2. Test it (works immediately via symlink)
3. Optionally commit: cd ~/.claude-profile && git add commands/status.md && git commit -m "Add status command"
```

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

### Telegram not responding
```bash
# Check listener
/ping in Telegram

# Restart listener
bun run ~/.claude/hooks/telegram-bun/index.ts listen
```

### Settings not applying
Restart Claude Code after running install script.

## License

MIT
