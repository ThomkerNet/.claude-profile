#!/usr/bin/env bash
#
# Claude Code Profile Sync Script
#
# Quick update script to sync changes from the repo to the active Claude profile.
# Run this after pulling updates from git.
#
# Usage:
#   cd ~/.claude-profile && git pull && ./sync.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Determine directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$SCRIPT_DIR}"
CLAUDE_HOME="$HOME/.claude"

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║     Claude Code Profile Sync               ║"
echo "╚════════════════════════════════════════════╝"
echo ""
log_info "Repository: $REPO_DIR"
log_info "Target:     $CLAUDE_HOME"
echo ""

# Verify Claude profile exists
if [ ! -d "$CLAUDE_HOME" ] || [ ! -f "$CLAUDE_HOME/.credentials.json" ]; then
    log_error "Claude profile not found at $CLAUDE_HOME"
    log_info "Please run bootstrap.sh first to set up the profile"
    exit 1
fi

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Darwin*)
        PLATFORM="mac"
        ;;
    Linux*)
        PLATFORM="linux"
        ;;
    CYGWIN*|MINGW*|MSYS*)
        PLATFORM="windows"
        ;;
    *)
        PLATFORM="unknown"
        ;;
esac

# Detect Bun path
if command -v bun &> /dev/null; then
    BUN_PATH="bun"
elif [ -f "$HOME/.bun/bin/bun" ]; then
    BUN_PATH="$HOME/.bun/bin/bun"
else
    log_warn "Bun not found, some features may not work"
    BUN_PATH="bun"
fi

# Helper to verify/fix symlink
verify_symlink() {
    local source=$1
    local target=$2
    local name=$3

    if [ ! -e "$source" ]; then
        log_warn "$name: source not found in repo"
        return 1
    fi

    if [ -L "$target" ]; then
        # It's a symlink, check if it points to the right place
        current_target=$(readlink "$target")
        if [ "$current_target" = "$source" ]; then
            log_success "$name: symlink OK"
            return 0
        else
            log_info "$name: updating symlink"
            rm "$target"
            ln -s "$source" "$target"
            log_success "$name: symlink updated"
            return 0
        fi
    elif [ -e "$target" ]; then
        # Target exists but is not a symlink
        log_warn "$name: not a symlink, backing up and creating symlink"
        mv "$target" "${target}.backup.$(date +%s)"
        ln -s "$source" "$target"
        log_success "$name: symlink created"
        return 0
    else
        # Target doesn't exist, create symlink
        log_info "$name: creating symlink"
        ln -s "$source" "$target"
        log_success "$name: symlink created"
        return 0
    fi
}

# Step 1: Pull latest changes
echo "── Step 1: Pull Updates ──"
if [ -d "$REPO_DIR/.git" ]; then
    log_info "Pulling latest changes..."
    cd "$REPO_DIR"
    if git pull --rebase; then
        log_success "Repository updated"
    else
        log_warn "Git pull failed, continuing with existing files"
    fi
else
    log_warn "Not a git repository, skipping pull"
fi

# Step 2: Verify/fix symlinks
echo ""
echo "── Step 2: Verify Symlinks ──"

verify_symlink "$REPO_DIR/commands" "$CLAUDE_HOME/commands" "commands/"
verify_symlink "$REPO_DIR/hooks" "$CLAUDE_HOME/hooks" "hooks/"
verify_symlink "$REPO_DIR/skills" "$CLAUDE_HOME/skills" "skills/"
verify_symlink "$REPO_DIR/agents" "$CLAUDE_HOME/agents" "agents/"
verify_symlink "$REPO_DIR/statuslines" "$CLAUDE_HOME/statuslines" "statuslines/"
verify_symlink "$REPO_DIR/tools" "$CLAUDE_HOME/tools" "tools/"
verify_symlink "$REPO_DIR/quota-fetcher" "$CLAUDE_HOME/quota-fetcher" "quota-fetcher/"

# Step 3: Update CLAUDE.md
echo ""
echo "── Step 3: Update CLAUDE.md ──"

if [ -f "$REPO_DIR/CLAUDE.md" ]; then
    if cp "$REPO_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"; then
        log_success "CLAUDE.md updated"
    else
        log_error "Failed to update CLAUDE.md"
    fi
else
    log_warn "CLAUDE.md not found in repo"
fi

# Step 4: Regenerate settings.json
echo ""
echo "── Step 4: Regenerate settings.json ──"

if [ -f "$REPO_DIR/settings.template.json" ]; then
    log_info "Regenerating settings.json from template..."

    # Select appropriate statusline script based on platform
    if [ "$PLATFORM" = "windows" ]; then
        STATUSLINE_PATH="$CLAUDE_HOME\\statuslines\\statusline.ps1"
    else
        STATUSLINE_PATH="$CLAUDE_HOME/statuslines/statusline.sh"
    fi

    if sed -e "s|{{BUN_PATH}}|$BUN_PATH|g" \
           -e "s|{{CLAUDE_HOME}}|$CLAUDE_HOME|g" \
           -e "s|{{STATUSLINE_PATH}}|$STATUSLINE_PATH|g" \
           "$REPO_DIR/settings.template.json" > "$CLAUDE_HOME/settings.json"; then
        log_success "settings.json regenerated"
    else
        log_error "Failed to regenerate settings.json"
    fi
else
    log_warn "settings.template.json not found in repo"
fi

# Step 5: Update hook dependencies if package.json changed
echo ""
echo "── Step 5: Hook Dependencies ──"

if [ -d "$REPO_DIR/hooks/telegram-bun" ]; then
    # Check if package.json was modified recently (within last git pull)
    if [ -f "$REPO_DIR/hooks/telegram-bun/package.json" ]; then
        log_info "Checking Telegram hook dependencies..."
        cd "$REPO_DIR/hooks/telegram-bun"

        # Always run bun install to be safe (it's fast if nothing changed)
        if $BUN_PATH install 2>/dev/null; then
            log_success "Telegram dependencies up to date"
        else
            log_warn "Bun install had warnings or failed"
        fi
        cd "$CLAUDE_HOME"
    fi
fi

# Step 6: Update MCP servers if config changed
echo ""
echo "── Step 6: MCP Servers ──"

if command -v claude &> /dev/null && [ -f "$REPO_DIR/mcp-servers.json" ]; then
    log_info "Checking MCP server configuration..."

    # For now, just inform the user
    # A full MCP server update requires removing and re-adding, which is disruptive
    # We'll only do this if the user explicitly requests it
    log_info "To update MCP servers, run: REPO_DIR=$REPO_DIR $REPO_DIR/setup.sh"
    log_info "  (This will reinstall all MCP servers from mcp-servers.json)"
else
    if ! command -v claude &> /dev/null; then
        log_warn "Claude CLI not available"
    fi
fi

# Step 7: Update secrets if needed
echo ""
echo "── Step 7: Secrets ──"

if [ -f "$REPO_DIR/secrets.json" ]; then
    log_info "Secrets file found in repo"
    log_info "To reapply secrets, run: REPO_DIR=$REPO_DIR $REPO_DIR/setup.sh"
else
    log_info "No secrets.json in repo (expected)"
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════╗"
echo -e "║  ${GREEN}Sync Complete!${NC}                             ║"
echo "╚════════════════════════════════════════════╝"
echo ""
log_success "Configuration synced from: $REPO_DIR"
log_success "Active Claude profile: $CLAUDE_HOME"
echo ""
log_info "Changes synced:"
echo "  ✓ Symlinks verified/updated"
echo "  ✓ CLAUDE.md updated"
echo "  ✓ settings.json regenerated"
echo "  ✓ Hook dependencies updated"
echo ""
log_info "If you need to reinstall MCP servers or secrets:"
echo "  REPO_DIR=$REPO_DIR $REPO_DIR/setup.sh"
echo ""
