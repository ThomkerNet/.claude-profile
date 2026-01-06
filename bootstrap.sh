#!/usr/bin/env bash
#
# Claude Code Profile Bootstrap Script
#
# This script handles FIRST-TIME setup on a new machine with the two-phase approach:
# Phase 1: Ensure Claude CLI is installed and logged in (creates ~/.claude)
# Phase 2: Install configuration from this repo into the active profile
#
# Usage:
#   1. Clone this repo: git clone https://github.com/ample-engineer/.claude.git ~/.claude-profile
#   2. Run: cd ~/.claude-profile && ./bootstrap.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step() { echo -e "${MAGENTA}▶${NC} $1"; }

# Determine repo and target directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$SCRIPT_DIR}"
CLAUDE_DIR="$HOME/.claude"

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   Claude Code Profile Bootstrap            ║"
echo "║   (Two-Phase Setup)                        ║"
echo "╚════════════════════════════════════════════╝"
echo ""
log_info "Repository: $REPO_DIR"
log_info "Target:     $CLAUDE_DIR"
echo ""

# Detect OS and package manager
OS="$(uname -s)"
case "$OS" in
    Linux*)
        PLATFORM="linux"
        if command -v apt-get &> /dev/null; then
            PKG_MANAGER="apt"
        elif command -v dnf &> /dev/null; then
            PKG_MANAGER="dnf"
        elif command -v yum &> /dev/null; then
            PKG_MANAGER="yum"
        elif command -v pacman &> /dev/null; then
            PKG_MANAGER="pacman"
        else
            PKG_MANAGER="unknown"
        fi
        ;;
    Darwin*)
        PLATFORM="mac"
        PKG_MANAGER="brew"
        ;;
    CYGWIN*|MINGW*|MSYS*)
        PLATFORM="windows"
        PKG_MANAGER="none"
        ;;
    *)
        PLATFORM="unknown"
        PKG_MANAGER="unknown"
        ;;
esac
log_info "Platform: $PLATFORM ($PKG_MANAGER)"

# Helper function to install packages
install_pkg() {
    local pkg=$1
    local brew_pkg=${2:-$1}

    case "$PKG_MANAGER" in
        apt)
            sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg"
            ;;
        dnf)
            sudo dnf install -y -q "$pkg"
            ;;
        yum)
            sudo yum install -y -q "$pkg"
            ;;
        pacman)
            sudo pacman -S --noconfirm "$pkg"
            ;;
        brew)
            brew install "$brew_pkg"
            ;;
        *)
            return 1
            ;;
    esac
}

#
# PHASE 1: Prerequisites & Claude CLI Installation
#
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  PHASE 1: Prerequisites & Claude CLI       ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Install Homebrew on Mac if missing
if [ "$PLATFORM" = "mac" ] && ! command -v brew &> /dev/null; then
    log_step "Installing Homebrew..."
    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null
        log_success "Homebrew installed"
    else
        log_error "Homebrew installation failed"
        exit 1
    fi
fi

# Git
if command -v git &> /dev/null; then
    log_success "Git installed: $(git --version | cut -d' ' -f3)"
else
    log_step "Installing Git..."
    if [ "$PLATFORM" = "mac" ]; then
        xcode-select --install 2>/dev/null || install_pkg git
    else
        install_pkg git
    fi
    log_success "Git installed"
fi

# Node.js & npm
if command -v node &> /dev/null && command -v npm &> /dev/null; then
    log_success "Node.js installed: $(node --version)"
else
    log_step "Installing Node.js..."
    if [ "$PLATFORM" = "mac" ]; then
        install_pkg node node
    elif [ "$PLATFORM" = "linux" ]; then
        if [ "$PKG_MANAGER" = "apt" ]; then
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs
        elif [ "$PKG_MANAGER" = "dnf" ] || [ "$PKG_MANAGER" = "yum" ]; then
            curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - && sudo $PKG_MANAGER install -y nodejs
        else
            install_pkg nodejs
        fi
    fi
    log_success "Node.js installed: $(node --version)"
fi

# Configure npm to use user directory (no sudo needed)
NPM_PREFIX="$HOME/.npm-global"
if [ ! -d "$NPM_PREFIX" ]; then
    mkdir -p "$NPM_PREFIX"
    npm config set prefix "$NPM_PREFIX"
    log_info "Configured npm to use $NPM_PREFIX (no sudo needed)"
fi

# Add to PATH for this session
export PATH="$NPM_PREFIX/bin:$PATH"

# Add to shell profile if not already there
if [ "$PLATFORM" = "mac" ]; then
    SHELL_PROFILE="$HOME/.zshrc"
    [ ! -f "$SHELL_PROFILE" ] && touch "$SHELL_PROFILE"
elif [ -f "$HOME/.zshrc" ]; then
    SHELL_PROFILE="$HOME/.zshrc"
else
    SHELL_PROFILE="$HOME/.bashrc"
fi

if ! grep -q "npm-global" "$SHELL_PROFILE" 2>/dev/null; then
    echo "" >> "$SHELL_PROFILE"
    echo "# npm global packages (added by Claude Code bootstrap)" >> "$SHELL_PROFILE"
    echo "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"" >> "$SHELL_PROFILE"
    log_info "Added npm-global to PATH in $SHELL_PROFILE"
fi

# Claude Code CLI
if command -v claude &> /dev/null; then
    log_success "Claude Code CLI installed: $(claude --version 2>/dev/null || echo 'version unknown')"
else
    log_step "Installing Claude Code CLI..."
    if npm install -g @anthropic-ai/claude-code 2>&1; then
        if command -v claude &> /dev/null; then
            log_success "Claude Code CLI installed"
        else
            log_warn "Claude Code CLI installed to $NPM_PREFIX/bin/claude"
            log_info "  Restart terminal or run: export PATH=\"\$HOME/.npm-global/bin:\$PATH\""
        fi
    else
        log_error "Claude Code CLI installation failed"
        exit 1
    fi
fi

#
# PHASE 2: Ensure Claude is Logged In
#
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  PHASE 2: Claude Login                     ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Check if already logged in
if [ -f "$CLAUDE_DIR/.credentials.json" ]; then
    log_success "Claude is already logged in"
    log_info "Active profile: $CLAUDE_DIR"
else
    log_warn "Claude is not logged in yet"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  REQUIRED: Please log in to Claude now"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "This will create the ~/.claude directory and credentials"
    echo ""
    read -p "Press ENTER when ready to open Claude CLI for login..." -r
    echo ""

    # Launch Claude CLI for login
    log_step "Launching Claude CLI..."
    echo ""
    echo "  → Please follow the login prompts"
    echo "  → After logging in, type 'exit' to return to this script"
    echo ""

    # Check if claude command is available
    if ! command -v claude &> /dev/null; then
        # Try using the npm-global path directly
        if [ -f "$NPM_PREFIX/bin/claude" ]; then
            log_info "Using: $NPM_PREFIX/bin/claude"
            "$NPM_PREFIX/bin/claude" || true
        else
            log_error "Claude CLI not found in PATH"
            log_info "Please run 'claude' manually to login, then re-run this script"
            exit 1
        fi
    else
        claude || true
    fi

    # Verify login succeeded
    echo ""
    if [ -f "$CLAUDE_DIR/.credentials.json" ]; then
        log_success "Login successful!"
    else
        log_error "Login failed or was cancelled"
        log_info "Please run 'claude' manually to login, then re-run this script"
        exit 1
    fi
fi

#
# PHASE 3: Install Configuration
#
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  PHASE 3: Install Configuration            ║"
echo "╚════════════════════════════════════════════╝"
echo ""

log_step "Running setup script..."
echo ""

# Run the main setup script with repo directory parameter
if [ -f "$REPO_DIR/setup.sh" ]; then
    # Make it executable
    chmod +x "$REPO_DIR/setup.sh"

    # Run with repo directory as parameter
    REPO_DIR="$REPO_DIR" "$REPO_DIR/setup.sh"
else
    log_error "setup.sh not found in $REPO_DIR"
    exit 1
fi

#
# Done!
#
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  Bootstrap Complete!                       ║"
echo "╚════════════════════════════════════════════╝"
echo ""
log_success "Claude Code profile installed"
log_info "Repository:    $REPO_DIR"
log_info "Active Profile: $CLAUDE_DIR"
echo ""
log_info "Next steps:"
echo "  1. Reload your shell: source $SHELL_PROFILE"
echo "  2. Run 'claude' to start Claude Code"
echo "  3. To update config: cd $REPO_DIR && git pull && ./sync.sh"
echo ""
