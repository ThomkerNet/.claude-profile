#!/usr/bin/env bash
#
# Claude Code Profile Setup Script (DSC Pattern)
#
# Idempotent, declarative configuration management.
# Safe to run multiple times - only changes what needs changing.
#
# Usage:
#   REPO_DIR=~/.claude-profile ./setup.sh
#   (or run via bootstrap.sh which sets REPO_DIR automatically)
#

set -e

# ============================================================================
# Setup & Load DSC Library
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$SCRIPT_DIR}"
CLAUDE_HOME="$HOME/.claude"

# Source DSC library
if [ -f "$REPO_DIR/lib/dsc.sh" ]; then
    source "$REPO_DIR/lib/dsc.sh"
else
    echo "Error: DSC library not found at $REPO_DIR/lib/dsc.sh"
    exit 1
fi

# ============================================================================
# Header
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   Claude Code Profile Setup (DSC)          ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "  Repository: $REPO_DIR"
echo "  Target:     $CLAUDE_HOME"
echo "  Platform:   $DSC_PLATFORM ($DSC_PKG_MANAGER)"
echo ""

# ============================================================================
# Prerequisites Check
# ============================================================================

if [ ! -f "$CLAUDE_HOME/.credentials.json" ]; then
    dsc_failed "Claude is not logged in!"
    echo "  Please run 'claude' to login first, then re-run this script"
    echo "  Or use bootstrap.sh which handles this automatically"
    exit 1
fi

# ============================================================================
# Admin Access Check (upfront for both platforms)
# ============================================================================

HAVE_SUDO=false
needs_sudo=false

# Detect if we'll need sudo for any operations
if [ "$DSC_PLATFORM" = "linux" ]; then
    [ ! -x "$(command -v jq)" ] && needs_sudo=true
    [ ! -x "$(command -v tmux)" ] && needs_sudo=true
elif [ "$DSC_PLATFORM" = "mac" ]; then
    # Check if Homebrew needs permission fixes
    if [ -d "/opt/homebrew" ]; then
        [ ! -w "/opt/homebrew/Cellar" ] && needs_sudo=true
        [ ! -w "/opt/homebrew/bin" ] && needs_sudo=true
    fi
fi

# Prompt for admin credentials upfront if needed
if [ "$needs_sudo" = true ]; then
    echo "── Admin Access Required ──"
    echo "  Some operations require administrator privileges."
    echo ""

    if ! command -v sudo &>/dev/null; then
        echo "  ⚠️  sudo is not available on this system."
        echo "  Some installations may fail. Continuing anyway..."
        dsc_skipped "admin:sudo (not available)"
    else
        echo "  Please enter your password to continue (or Ctrl+C to skip):"
        # Use || true to prevent set -e from exiting on sudo failure
        if sudo -v 2>/dev/null; then
            HAVE_SUDO=true
            dsc_changed "admin:sudo (credentials cached)"
            # Keep sudo alive in background
            (while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done) &
        else
            echo "  ⚠️  Could not obtain admin privileges."
            echo "  Some installations may fail. Continuing anyway..."
            dsc_skipped "admin:sudo (auth failed)"
        fi
    fi
    echo ""
fi

# ============================================================================
# Homebrew Permissions Fix (macOS only, requires sudo)
# ============================================================================

if [ "$DSC_PLATFORM" = "mac" ] && [ -d "/opt/homebrew" ]; then
    # Check if Homebrew directories are writable
    if [ ! -w "/opt/homebrew/Cellar" ] || [ ! -w "/opt/homebrew/bin" ]; then
        echo ""
        echo "── Homebrew Permissions Fix ──"

        if [ "$HAVE_SUDO" = true ]; then
            # Fix ownership for current user
            if sudo chown -R "$(whoami)" /opt/homebrew 2>/dev/null; then
                dsc_changed "fix:homebrew-permissions (fixed for $(whoami))"
            else
                dsc_failed "fix:homebrew-permissions"
            fi

            # Also fix for admin group to allow other admin users
            if sudo chgrp -R admin /opt/homebrew 2>/dev/null && sudo chmod -R g+w /opt/homebrew 2>/dev/null; then
                dsc_changed "fix:homebrew-admin-group (admin group has write access)"
            fi
        else
            dsc_skipped "fix:homebrew-permissions (no sudo)"
            echo "  To fix manually: sudo chown -R $(whoami) /opt/homebrew"
        fi
    fi
fi

# ============================================================================
# Step 1: System Packages
# ============================================================================

echo ""
echo "── Step 1: System Packages ──"

ensure_package "jq"
ensure_package "git"
[ "$DSC_PLATFORM" != "windows" ] && ensure_package "tmux"

# ============================================================================
# Step 2: Runtime Environments
# ============================================================================

echo ""
echo "── Step 2: Runtime Environments ──"

# Bun
BUN_PATH=""
if command -v bun &>/dev/null; then
    BUN_PATH="bun"
    dsc_unchanged "runtime:bun ($(bun --version))"
elif [ -f "$HOME/.bun/bin/bun" ]; then
    BUN_PATH="$HOME/.bun/bin/bun"
    dsc_unchanged "runtime:bun ($($BUN_PATH --version))"
else
    echo -e "  ${_BLUE}Installing Bun...${_NC}"
    if curl -fsSL https://bun.sh/install | bash 2>&1 | grep -E "Installed|bun was" | head -2 | sed 's/^/    /'; then
        export PATH="$HOME/.bun/bin:$PATH"
        BUN_PATH="$HOME/.bun/bin/bun"
        ensure_profile_entry "bun" 'export PATH="$HOME/.bun/bin:$PATH"'
        dsc_changed "runtime:bun (installed)"
    else
        dsc_failed "runtime:bun"
    fi
fi

# ============================================================================
# Step 3: CLI Tools
# ============================================================================

echo ""
echo "── Step 3: CLI Tools ──"

# Gemini CLI
ensure_npm_package "@google/gemini-cli" "gemini"

# GitHub Copilot CLI
if command -v gh &>/dev/null && gh extension list 2>/dev/null | grep -q copilot; then
    dsc_unchanged "npm:gh-copilot (installed as gh extension)"
else
    ensure_npm_package "@github/copilot" "copilot"
fi

# Bitwarden CLI
ensure_npm_package "@bitwarden/cli" "bw"

# Configure Bitwarden server if installed
if command -v bw &>/dev/null || [ -f "$HOME/.npm-global/bin/bw" ]; then
    BW_CMD=$(command -v bw || echo "$HOME/.npm-global/bin/bw")
    current_server=$($BW_CMD config server 2>/dev/null || echo "")
    if [ "$current_server" = "https://vault.boroughnexus.com" ]; then
        dsc_unchanged "config:bitwarden-server"
    else
        if $BW_CMD config server "https://vault.boroughnexus.com" &>/dev/null; then
            dsc_changed "config:bitwarden-server (set to vault.boroughnexus.com)"
        else
            dsc_failed "config:bitwarden-server"
        fi
    fi
fi

# Glances (system monitoring)
if [ "$DSC_PLATFORM" = "mac" ]; then
    if command -v glances &>/dev/null; then
        dsc_unchanged "pip:glances"
    elif command -v brew &>/dev/null; then
        echo -e "  ${_BLUE}Installing glances via Homebrew...${_NC}"
        if brew install glances &>/dev/null; then
            dsc_changed "brew:glances (installed)"
        else
            dsc_failed "brew:glances"
        fi
    else
        ensure_pip_package "glances" "glances"
    fi
else
    ensure_pip_package "glances" "glances"
fi

# ============================================================================
# Step 4: Configuration Symlinks
# ============================================================================

echo ""
echo "── Step 4: Configuration Symlinks ──"

ensure_directory "$CLAUDE_HOME"
ensure_directory "$CLAUDE_HOME/logs"

ensure_symlink "$REPO_DIR/commands" "$CLAUDE_HOME/commands" "commands/"
ensure_symlink "$REPO_DIR/hooks" "$CLAUDE_HOME/hooks" "hooks/"
ensure_symlink "$REPO_DIR/skills" "$CLAUDE_HOME/skills" "skills/"
ensure_symlink "$REPO_DIR/scripts" "$CLAUDE_HOME/scripts" "scripts/"
ensure_symlink "$REPO_DIR/agents" "$CLAUDE_HOME/agents" "agents/"
ensure_symlink "$REPO_DIR/statuslines" "$CLAUDE_HOME/statuslines" "statuslines/"
ensure_symlink "$REPO_DIR/tools" "$CLAUDE_HOME/tools" "tools/"
ensure_symlink "$REPO_DIR/quota-fetcher" "$CLAUDE_HOME/quota-fetcher" "quota-fetcher/"
ensure_symlink "$REPO_DIR/services" "$CLAUDE_HOME/services" "services/"
ensure_symlink "$REPO_DIR/lib" "$CLAUDE_HOME/lib" "lib/"

# CLAUDE.md is copied (not symlinked) because Claude reads it directly
ensure_file_copy "$REPO_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md" "CLAUDE.md"

# ============================================================================
# Step 5: Settings & Templates
# ============================================================================

echo ""
echo "── Step 5: Settings & Templates ──"

# Determine paths for template substitution
if [ "$DSC_PLATFORM" = "windows" ]; then
    STATUSLINE_PATH="$CLAUDE_HOME\\statuslines\\statusline.ps1"
else
    STATUSLINE_PATH="$CLAUDE_HOME/statuslines/statusline.sh"
fi

ensure_file_template "$REPO_DIR/settings.template.json" "$CLAUDE_HOME/settings.json" \
    "{{BUN_PATH}}=$BUN_PATH" \
    "{{CLAUDE_HOME}}=$CLAUDE_HOME" \
    "{{STATUSLINE_PATH}}=$STATUSLINE_PATH"

# ============================================================================
# Step 6: Hook Dependencies
# ============================================================================

echo ""
echo "── Step 6: Hook Dependencies ──"

if [ -d "$REPO_DIR/hooks/telegram-bun" ] && [ -n "$BUN_PATH" ]; then
    # Check if node_modules exists and is current
    if [ -d "$REPO_DIR/hooks/telegram-bun/node_modules" ]; then
        dsc_unchanged "deps:telegram-bun"
    else
        echo -e "  ${_BLUE}Installing Telegram dependencies...${_NC}"
        (cd "$REPO_DIR/hooks/telegram-bun" && $BUN_PATH install 2>&1 | grep -E "packages|Done" | head -2 | sed 's/^/    /')
        if [ -d "$REPO_DIR/hooks/telegram-bun/node_modules" ]; then
            dsc_changed "deps:telegram-bun (installed)"
        else
            dsc_failed "deps:telegram-bun"
        fi
    fi
fi

if [ -d "$REPO_DIR/quota-fetcher" ] && [ -n "$BUN_PATH" ]; then
    if [ -d "$REPO_DIR/quota-fetcher/node_modules" ]; then
        dsc_unchanged "deps:quota-fetcher"
    else
        echo -e "  ${_BLUE}Installing quota-fetcher dependencies...${_NC}"
        (cd "$REPO_DIR/quota-fetcher" && $BUN_PATH install 2>&1 | grep -E "packages|Done" | head -2 | sed 's/^/    /')
        if [ -d "$REPO_DIR/quota-fetcher/node_modules" ]; then
            dsc_changed "deps:quota-fetcher (installed)"
        else
            dsc_failed "deps:quota-fetcher"
        fi
    fi
fi

# ============================================================================
# Step 7: Shell Profile Entries
# ============================================================================

echo ""
echo "── Step 7: Shell Profile ──"

ensure_profile_entry "npm-global" 'export PATH="$HOME/.npm-global/bin:$PATH"'
ensure_profile_entry "local-bin" 'export PATH="$HOME/.local/bin:$PATH"'

# Apply secrets if available
if [ -f "$REPO_DIR/secrets.json" ] && command -v jq &>/dev/null; then
    FIRECRAWL_KEY=$(jq -r '.api_keys.firecrawl // empty' "$REPO_DIR/secrets.json")
    if [ -n "$FIRECRAWL_KEY" ] && [ "$FIRECRAWL_KEY" != "YOUR_FIRECRAWL_API_KEY" ]; then
        ensure_profile_entry "FIRECRAWL_API_KEY" "export FIRECRAWL_API_KEY='$FIRECRAWL_KEY'"
    fi
fi

# ============================================================================
# Step 8: Services (launchd/systemd)
# ============================================================================

echo ""
echo "── Step 8: Background Services ──"

if [ "$DSC_PLATFORM" = "mac" ]; then
    ensure_directory "$HOME/Library/LaunchAgents"

    # Glances monitoring service
    if [ -f "$REPO_DIR/services/com.claude.glances.plist" ]; then
        GLANCES_PLIST="$HOME/Library/LaunchAgents/com.claude.glances.plist"
        ensure_file_template "$REPO_DIR/services/com.claude.glances.plist" "$GLANCES_PLIST" \
            "{{HOME}}=$HOME" \
            "{{CLAUDE_HOME}}=$CLAUDE_HOME"

        # Load service if not running
        if ! launchctl list 2>/dev/null | grep -q "com.claude.glances"; then
            if launchctl load "$GLANCES_PLIST" 2>/dev/null; then
                dsc_changed "service:com.claude.glances (started)"
            else
                dsc_failed "service:com.claude.glances (load failed)"
            fi
        else
            dsc_unchanged "service:com.claude.glances (running)"
        fi
    fi

    # Quota fetcher service
    if [ -f "$REPO_DIR/quota-fetcher/com.claude.quota-fetcher.plist.template" ]; then
        QUOTA_PLIST="$HOME/Library/LaunchAgents/com.claude.quota-fetcher.plist"
        ensure_file_template "$REPO_DIR/quota-fetcher/com.claude.quota-fetcher.plist.template" "$QUOTA_PLIST" \
            "{{HOME}}=$HOME" \
            "{{CLAUDE_HOME}}=$CLAUDE_HOME"
        dsc_info "Quota fetcher plist installed. Start with: launchctl load $QUOTA_PLIST"
    fi

    # Spec watcher tools (per-project, not a daemon)
    # Make watcher scripts executable for manual/hook use
    chmod +x "$REPO_DIR/services/spec-watcher/watcher.sh" 2>/dev/null || true
    ensure_directory "$CLAUDE_HOME/.spec-plans"
    dsc_unchanged "tools:spec-watcher (available)"

elif [ "$DSC_PLATFORM" = "linux" ]; then
    ensure_directory "$HOME/.config/systemd/user"

    # Glances monitoring timer
    if [ -f "$REPO_DIR/services/glances.service" ] && [ -f "$REPO_DIR/services/glances.timer" ]; then
        ensure_file_template "$REPO_DIR/services/glances.service" "$HOME/.config/systemd/user/glances.service" \
            "{{HOME}}=$HOME" \
            "{{CLAUDE_HOME}}=$CLAUDE_HOME"
        ensure_file_copy "$REPO_DIR/services/glances.timer" "$HOME/.config/systemd/user/glances.timer" "glances.timer"

        systemctl --user daemon-reload 2>/dev/null || true
        if ! systemctl --user is-enabled glances.timer &>/dev/null; then
            if systemctl --user enable --now glances.timer 2>/dev/null; then
                dsc_changed "service:glances.timer (enabled)"
            else
                dsc_failed "service:glances.timer"
            fi
        else
            dsc_unchanged "service:glances.timer (enabled)"
        fi
    fi

    # Spec watcher tools (per-project, not a daemon)
    chmod +x "$REPO_DIR/services/spec-watcher/watcher.sh" 2>/dev/null || true
    ensure_directory "$CLAUDE_HOME/.spec-plans"
    dsc_unchanged "tools:spec-watcher (available)"
fi

# ============================================================================
# Step 9: tmux Configuration
# ============================================================================

echo ""
echo "── Step 9: Terminal Configuration ──"

if [ "$DSC_PLATFORM" != "windows" ] && command -v tmux &>/dev/null; then
    ensure_file_copy "$REPO_DIR/tmux.conf" "$HOME/.tmux.conf" "tmux.conf"

    # tmux plugins
    TMUX_PLUGINS="$HOME/.tmux/plugins"
    ensure_directory "$TMUX_PLUGINS"

    # TPM
    if [ ! -d "$TMUX_PLUGINS/tpm" ]; then
        if git clone --depth 1 https://github.com/tmux-plugins/tpm "$TMUX_PLUGINS/tpm" &>/dev/null; then
            dsc_changed "git:tpm (cloned)"
        else
            dsc_failed "git:tpm"
        fi
    else
        dsc_unchanged "git:tpm"
    fi

    # tmux-resurrect
    if [ ! -d "$TMUX_PLUGINS/tmux-resurrect" ]; then
        if git clone --depth 1 https://github.com/tmux-plugins/tmux-resurrect "$TMUX_PLUGINS/tmux-resurrect" &>/dev/null; then
            dsc_changed "git:tmux-resurrect (cloned)"
        else
            dsc_failed "git:tmux-resurrect"
        fi
    else
        dsc_unchanged "git:tmux-resurrect"
    fi

    # tmux-continuum
    if [ ! -d "$TMUX_PLUGINS/tmux-continuum" ]; then
        if git clone --depth 1 https://github.com/tmux-plugins/tmux-continuum "$TMUX_PLUGINS/tmux-continuum" &>/dev/null; then
            dsc_changed "git:tmux-continuum (cloned)"
        else
            dsc_failed "git:tmux-continuum"
        fi
    else
        dsc_unchanged "git:tmux-continuum"
    fi
fi

# ============================================================================
# Step 10: Applications
# ============================================================================

echo ""
echo "── Step 10: Applications ──"

# Obsidian
if [ "$DSC_PLATFORM" = "mac" ]; then
    if [ -d "/Applications/Obsidian.app" ]; then
        dsc_unchanged "app:Obsidian"
    elif command -v brew &>/dev/null; then
        echo -e "  ${_BLUE}Installing Obsidian...${_NC}"
        if brew install --cask obsidian &>/dev/null; then
            dsc_changed "app:Obsidian (installed)"
        else
            dsc_failed "app:Obsidian"
        fi
    fi

    # Vault directory
    ensure_directory "$HOME/Obsidian/Simon-Personal"
fi

# ============================================================================
# Step 11: MCP Servers (Interactive)
# ============================================================================

echo ""
echo "── Step 11: MCP Servers ──"

if command -v claude &>/dev/null && [ -f "$REPO_DIR/mcp-servers.json" ] && command -v jq &>/dev/null; then
    # Get list of currently installed MCP servers
    INSTALLED_SERVERS=$(claude mcp list -s user 2>/dev/null | grep -E "^\s+\w" | awk '{print $1}' || echo "")

    jq -c '.servers[]' "$REPO_DIR/mcp-servers.json" 2>/dev/null | while IFS= read -r row; do
        name=$(echo "$row" | jq -r '.name')
        cmd=$(echo "$row" | jq -r '.command')

        # Check if already installed
        if echo "$INSTALLED_SERVERS" | grep -q "^${name}$"; then
            dsc_unchanged "mcp:$name"
            continue
        fi

        # Build env args
        env_args=""
        if echo "$row" | jq -e '.env' >/dev/null 2>&1; then
            while IFS='=' read -r key value; do
                [ -z "$key" ] && continue
                value=$(echo "$value" | sed -e "s|{{CLAUDE_HOME}}|$CLAUDE_HOME|g" \
                                            -e "s|{{REPO_DIR}}|$REPO_DIR|g" \
                                            -e "s|{{HOME}}|$HOME|g" \
                                            -e "s|{{BUN_PATH}}|$BUN_PATH|g")
                # Skip if placeholder not resolved
                echo "$value" | grep -q '{{' && continue
                env_args="$env_args -e $key=$value"
            done < <(echo "$row" | jq -r '.env | to_entries[] | "\(.key)=\(.value)"')
        fi

        # Install MCP server
        if eval "claude mcp add \"$name\" --transport stdio -s user $env_args -- $cmd" &>/dev/null; then
            dsc_changed "mcp:$name (added)"
        else
            dsc_failed "mcp:$name"
        fi
    done
else
    dsc_skipped "mcp:servers (claude CLI or jq not available)"
fi

# ============================================================================
# Step 12: Secrets (Interactive)
# ============================================================================

echo ""
echo "── Step 12: Secrets ──"

if [ -f "$REPO_DIR/secrets.json" ] && command -v jq &>/dev/null; then
    BOT_TOKEN=$(jq -r '.telegram.bot_token // empty' "$REPO_DIR/secrets.json")
    CHAT_ID=$(jq -r '.telegram.chat_id // empty' "$REPO_DIR/secrets.json")

    if [ -n "$BOT_TOKEN" ] && [ "$BOT_TOKEN" != "YOUR_BOT_TOKEN" ] && [ -n "$BUN_PATH" ]; then
        # Check if already configured
        if [ -f "$CLAUDE_HOME/.telegram-config.json" ]; then
            dsc_unchanged "config:telegram"
        else
            if $BUN_PATH run "$REPO_DIR/hooks/telegram-bun/index.ts" config "$BOT_TOKEN" "$CHAT_ID" &>/dev/null; then
                dsc_changed "config:telegram (configured)"
            else
                dsc_failed "config:telegram"
            fi
        fi
    fi
    dsc_unchanged "secrets:applied"
else
    dsc_skipped "secrets (no secrets.json or jq missing)"
fi

# ============================================================================
# Summary
# ============================================================================

dsc_summary

# ============================================================================
# Post-Install Information
# ============================================================================

echo ""
echo "── Next Steps ──"

SHELL_NAME=$(basename "$SHELL")
case "$SHELL_NAME" in
    zsh)  RELOAD_CMD="source ~/.zshrc" ;;
    bash) RELOAD_CMD="source ~/.bashrc" ;;
    *)    RELOAD_CMD="source ~/.profile" ;;
esac

echo "  1. Reload shell: $RELOAD_CMD"
echo "  2. Run 'claude' to start Claude Code"

command -v gemini &>/dev/null && echo "  3. Run 'gemini' to login (first time)"
command -v bw &>/dev/null && echo "  4. Run 'bw login' for Vaultwarden access"

echo ""
