#!/usr/bin/env bash
#
# Claude Code Profile Setup Script
#
# This script installs configuration from the repo into the active Claude profile.
# Works with the two-phase bootstrap approach.
#
# Usage:
#   REPO_DIR=~/.claude-profile ./setup.sh
#   (or run via bootstrap.sh which sets REPO_DIR automatically)
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

# Track failures for summary
FAILURES=()
add_failure() { FAILURES+=("$1"); }

# Determine directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$SCRIPT_DIR}"
CLAUDE_HOME="$HOME/.claude"

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║     Claude Code Profile Setup              ║"
echo "╚════════════════════════════════════════════╝"
echo ""
log_info "Repository: $REPO_DIR"
log_info "Target:     $CLAUDE_HOME"
echo ""

# Verify Claude is logged in
if [ ! -f "$CLAUDE_HOME/.credentials.json" ]; then
    log_error "Claude is not logged in!"
    log_info "Please run 'claude' to login first, then re-run this script"
    log_info "Or use bootstrap.sh which handles this automatically"
    exit 1
fi

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

# Helper to create symlink safely
create_symlink() {
    local source=$1
    local target=$2
    local name=$3

    if [ -e "$target" ] && [ ! -L "$target" ]; then
        # Target exists and is not a symlink - back it up
        log_warn "$name exists, backing up to ${target}.backup.$(date +%s)"
        mv "$target" "${target}.backup.$(date +%s)"
    elif [ -L "$target" ]; then
        # Remove existing symlink
        rm "$target"
    fi

    if [ -e "$source" ]; then
        ln -s "$source" "$target"
        log_success "$name symlinked"
    else
        log_warn "$name not found in repo: $source"
        add_failure "$name (not in repo)"
    fi
}

# Step 1: Install System Dependencies
echo ""
echo "── Step 1: System Dependencies ──"

# jq (for JSON parsing)
if command -v jq &> /dev/null; then
    log_success "jq installed"
else
    log_info "Installing jq..."
    if install_pkg jq jq 2>/dev/null; then
        log_success "jq installed"
    else
        log_warn "Could not install jq - some features may not work"
        add_failure "jq (optional)"
    fi
fi

# tmux (terminal multiplexer - macOS/Linux)
if [ "$PLATFORM" != "windows" ]; then
    if command -v tmux &> /dev/null; then
        log_success "tmux installed: $(tmux -V)"
    else
        log_info "Installing tmux..."
        if install_pkg tmux tmux 2>/dev/null; then
            log_success "tmux installed"
        else
            log_warn "Could not install tmux - optional for development"
            add_failure "tmux (optional)"
        fi
    fi
fi

# Bun
if command -v bun &> /dev/null; then
    BUN_PATH="bun"
    log_success "Bun installed: $(bun --version)"
elif [ -f "$HOME/.bun/bin/bun" ]; then
    BUN_PATH="$HOME/.bun/bin/bun"
    log_success "Bun installed: $($BUN_PATH --version)"
else
    log_info "Installing Bun..."
    if curl -fsSL https://bun.sh/install | bash; then
        export PATH="$HOME/.bun/bin:$PATH"
        BUN_PATH="$HOME/.bun/bin/bun"
        if [ -f "$BUN_PATH" ]; then
            log_success "Bun installed: $($BUN_PATH --version)"

            # Add Bun to shell profile for persistent PATH
            if [ "$PLATFORM" = "mac" ]; then
                SHELL_PROFILE="$HOME/.zshrc"
                [ ! -f "$SHELL_PROFILE" ] && touch "$SHELL_PROFILE"
            elif [ -f "$HOME/.zshrc" ]; then
                SHELL_PROFILE="$HOME/.zshrc"
            else
                SHELL_PROFILE="$HOME/.bashrc"
            fi
            if ! grep -q "\.bun/bin" "$SHELL_PROFILE" 2>/dev/null; then
                echo "" >> "$SHELL_PROFILE"
                echo "# Bun (added by Claude Code installer)" >> "$SHELL_PROFILE"
                echo "export PATH=\"\$HOME/.bun/bin:\$PATH\"" >> "$SHELL_PROFILE"
                log_info "Added Bun to PATH in $SHELL_PROFILE"
            fi
        else
            log_error "Bun installation failed"
            add_failure "Bun"
        fi
    else
        log_error "Bun installation failed"
        log_info "  Install manually: curl -fsSL https://bun.sh/install | bash"
        add_failure "Bun"
    fi
fi

# Gemini CLI
if command -v gemini &> /dev/null; then
    log_success "Gemini CLI installed"
else
    log_info "Installing Gemini CLI..."
    if command -v npm &> /dev/null; then
        if npm install -g @google/gemini-cli 2>&1; then
            if command -v gemini &> /dev/null; then
                log_success "Gemini CLI installed"
                log_info "  Run 'gemini' to login interactively on first use"
            else
                log_warn "Gemini CLI installed but not in PATH yet (restart terminal)"
            fi
        else
            log_warn "Could not install Gemini CLI"
            log_info "  Install manually: npm install -g @google/gemini-cli"
            add_failure "Gemini CLI (optional)"
        fi
    else
        log_warn "npm not available, skipping Gemini CLI install"
        add_failure "Gemini CLI (npm missing)"
    fi
fi

# GitHub Copilot CLI (for terminal assistance & GitHub operations)
COPILOT_INSTALLED=false
if command -v copilot &> /dev/null; then
    log_success "GitHub Copilot CLI installed"
    COPILOT_INSTALLED=true
else
    log_info "Installing GitHub Copilot CLI..."
    NPM_PREFIX="$HOME/.npm-global"

    if [ "$PLATFORM" = "mac" ]; then
        # Prefer Homebrew on Mac
        if command -v brew &> /dev/null; then
            if brew install github/gh/gh 2>/dev/null && gh extension install github/gh-copilot 2>/dev/null; then
                log_success "GitHub Copilot CLI installed via Homebrew"
                COPILOT_INSTALLED=true
            else
                log_warn "Homebrew install failed, trying npm..."
            fi
        fi
    fi

    # Fall back to npm on all platforms
    if [ "$COPILOT_INSTALLED" = false ] && command -v npm &> /dev/null; then
        if npm install -g @github/copilot 2>&1; then
            if command -v copilot &> /dev/null || [ -f "$NPM_PREFIX/bin/copilot" ]; then
                log_success "GitHub Copilot CLI installed via npm"
                COPILOT_INSTALLED=true
            else
                log_warn "GitHub Copilot CLI installed but not in PATH yet (restart terminal)"
                COPILOT_INSTALLED=true
            fi
        else
            log_warn "Could not install GitHub Copilot CLI"
            log_info "  Install manually: npm install -g @github/copilot"
            log_info "  Requires GitHub Copilot Pro subscription"
            add_failure "GitHub Copilot CLI (optional)"
        fi
    elif [ "$COPILOT_INSTALLED" = false ]; then
        log_warn "npm not available, skipping GitHub Copilot CLI install"
        add_failure "GitHub Copilot CLI (npm missing)"
    fi
fi

# Bitwarden CLI (for Vaultwarden access)
BW_INSTALLED=false
if command -v bw &> /dev/null; then
    log_success "Bitwarden CLI installed: $(bw --version 2>/dev/null || echo 'version unknown')"
    BW_INSTALLED=true
else
    log_info "Installing Bitwarden CLI..."
    NPM_PREFIX="$HOME/.npm-global"
    if command -v npm &> /dev/null; then
        if npm install -g @bitwarden/cli 2>&1; then
            if [ -f "$NPM_PREFIX/bin/bw" ] || command -v bw &> /dev/null; then
                log_success "Bitwarden CLI installed"
                BW_INSTALLED=true
            else
                log_warn "Bitwarden CLI installed but not in PATH yet (restart terminal)"
                BW_INSTALLED=true
            fi
        else
            log_warn "Could not install Bitwarden CLI"
            log_info "  Install manually: npm install -g @bitwarden/cli"
            add_failure "Bitwarden CLI (optional)"
        fi
    else
        log_warn "npm not available, skipping Bitwarden CLI install"
        add_failure "Bitwarden CLI (npm missing)"
    fi
fi

# Configure Bitwarden for Vaultwarden server
if [ "$BW_INSTALLED" = true ]; then
    VAULTWARDEN_SERVER="https://vault.boroughnexus.com"
    NPM_PREFIX="$HOME/.npm-global"
    if command -v bw &> /dev/null; then
        BW_CMD="bw"
    elif [ -f "$NPM_PREFIX/bin/bw" ]; then
        BW_CMD="$NPM_PREFIX/bin/bw"
    else
        BW_CMD=""
    fi

    if [ -n "$BW_CMD" ]; then
        log_info "Configuring Bitwarden for Vaultwarden..."
        if $BW_CMD config server "$VAULTWARDEN_SERVER" 2>/dev/null; then
            log_success "Bitwarden configured for $VAULTWARDEN_SERVER"
        else
            log_warn "Could not configure Bitwarden server (may already be set)"
        fi
    fi
fi

# Offer to set up Keychain credentials for Claude autonomous vault access (macOS only)
if [[ "$OSTYPE" == "darwin"* ]] && command -v bun &> /dev/null; then
    KEYCHAIN_SETUP="$REPO_DIR/tools/vaultwarden/setup-keychain.ts"
    if [ -f "$KEYCHAIN_SETUP" ]; then
        echo ""
        log_info "Vault Keychain Setup (optional)"
        log_info "  Stores claude@boroughnexus.com API credentials in Secure Enclave"
        log_info "  Enables Claude autonomous RO access to BNX vault"
        echo ""
        read -p "Set up Keychain credentials now? (y/N): " setup_keychain
        if [[ "$setup_keychain" =~ ^[Yy]$ ]]; then
            bun run "$KEYCHAIN_SETUP"
        else
            log_info "Skipped. Run later: bun run $KEYCHAIN_SETUP"
        fi
    fi
fi

# Step 2: Create Symlinks
echo ""
echo "── Step 2: Configuration Symlinks ──"

# Create symlinks for directories that should sync with repo
create_symlink "$REPO_DIR/commands" "$CLAUDE_HOME/commands" "commands/"
create_symlink "$REPO_DIR/hooks" "$CLAUDE_HOME/hooks" "hooks/"
create_symlink "$REPO_DIR/skills" "$CLAUDE_HOME/skills" "skills/"
create_symlink "$REPO_DIR/agents" "$CLAUDE_HOME/agents" "agents/"
create_symlink "$REPO_DIR/statuslines" "$CLAUDE_HOME/statuslines" "statuslines/"
create_symlink "$REPO_DIR/tools" "$CLAUDE_HOME/tools" "tools/"
create_symlink "$REPO_DIR/quota-fetcher" "$CLAUDE_HOME/quota-fetcher" "quota-fetcher/"

# Copy CLAUDE.md (not symlink, since Claude reads it directly)
if [ -f "$REPO_DIR/CLAUDE.md" ]; then
    cp "$REPO_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
    log_success "CLAUDE.md copied"
else
    log_warn "CLAUDE.md not found in repo"
    add_failure "CLAUDE.md (not in repo)"
fi

# Step 3: Generate settings.json
echo ""
echo "── Step 3: Generate settings.json ──"

if [ -f "$REPO_DIR/settings.template.json" ]; then
    log_info "Generating settings.json from template..."

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
        log_success "settings.json generated"
    else
        log_error "Failed to generate settings.json"
        add_failure "settings.json"
    fi
else
    log_warn "settings.template.json not found in repo"
    add_failure "settings.template.json (not in repo)"
fi

# Step 4: Install hook dependencies
echo ""
echo "── Step 4: Hook Dependencies ──"

if [ -d "$REPO_DIR/hooks/telegram-bun" ]; then
    log_info "Installing Telegram integration dependencies..."
    cd "$REPO_DIR/hooks/telegram-bun"
    if $BUN_PATH install 2>/dev/null; then
        log_success "Telegram dependencies installed"
    else
        log_warn "Bun install had warnings or failed"
        add_failure "Telegram dependencies (optional)"
    fi
    cd "$CLAUDE_HOME"
fi

# Make scripts executable
chmod +x "$REPO_DIR/setup.sh" "$REPO_DIR/hooks/telegram-bun/run.sh" 2>/dev/null || true

# Step 5: Apply secrets from repo
echo ""
echo "── Step 5: Secrets ──"

if [ -f "$REPO_DIR/secrets.json" ]; then
    log_info "Applying secrets from secrets.json..."
    if command -v jq &> /dev/null; then
        BOT_TOKEN=$(jq -r '.telegram.bot_token // empty' "$REPO_DIR/secrets.json")
        CHAT_ID=$(jq -r '.telegram.chat_id // empty' "$REPO_DIR/secrets.json")

        if [ -n "$BOT_TOKEN" ] && [ "$BOT_TOKEN" != "YOUR_BOT_TOKEN" ]; then
            log_info "Configuring Telegram..."
            if $BUN_PATH run "$REPO_DIR/hooks/telegram-bun/index.ts" config "$BOT_TOKEN" "$CHAT_ID"; then
                log_success "Telegram configured"
            else
                log_warn "Telegram configuration may have failed"
                add_failure "Telegram config (optional)"
            fi
        fi

        # Export API keys as env vars
        FIRECRAWL_KEY=$(jq -r '.api_keys.firecrawl // empty' "$REPO_DIR/secrets.json")

        if [ -n "$FIRECRAWL_KEY" ] && [ "$FIRECRAWL_KEY" != "YOUR_FIRECRAWL_API_KEY" ]; then
            log_info "Found Firecrawl API key - adding to shell profile..."
            # Prefer zshrc on Mac (default shell), create if needed
            if [ "$PLATFORM" = "mac" ]; then
                SHELL_PROFILE="$HOME/.zshrc"
                [ ! -f "$SHELL_PROFILE" ] && touch "$SHELL_PROFILE"
            elif [ -f "$HOME/.zshrc" ]; then
                SHELL_PROFILE="$HOME/.zshrc"
            else
                SHELL_PROFILE="$HOME/.bashrc"
            fi

            if ! grep -q "FIRECRAWL_API_KEY" "$SHELL_PROFILE" 2>/dev/null; then
                echo "" >> "$SHELL_PROFILE"
                echo "# Firecrawl API key (added by Claude Code installer)" >> "$SHELL_PROFILE"
                echo "export FIRECRAWL_API_KEY='$FIRECRAWL_KEY'" >> "$SHELL_PROFILE"
                log_success "Firecrawl API key added to $SHELL_PROFILE"
            else
                log_info "Firecrawl API key already in $SHELL_PROFILE"
            fi
        fi
        log_success "Secrets applied"
    else
        log_warn "jq not installed, cannot parse secrets.json"
        log_info "  Install jq and re-run to apply secrets"
        add_failure "Secrets (jq missing)"
    fi
else
    log_info "No secrets.json found - create one from secrets.template.json"
fi

# Step 6: Install MCP Servers
echo ""
echo "── Step 6: MCP Servers ──"

if command -v claude &> /dev/null && [ -f "$REPO_DIR/mcp-servers.json" ]; then
    log_info "Installing MCP servers..."

    # Parse mcp-servers.json and install each
    if command -v jq &> /dev/null; then
        # Use while loop to handle JSON properly
        jq -c '.servers[]' "$REPO_DIR/mcp-servers.json" | while IFS= read -r row; do
            name=$(echo "$row" | jq -r '.name')
            cmd=$(echo "$row" | jq -r '.command')

            # Build env var arguments
            env_args=""
            if echo "$row" | jq -e '.env' >/dev/null 2>&1; then
                # Extract env vars and substitute placeholders
                while IFS='=' read -r key value; do
                    # Skip if key is empty
                    [ -z "$key" ] && continue
                    # Substitute known placeholders
                    value=$(echo "$value" | sed -e "s|{{CLAUDE_HOME}}|$CLAUDE_HOME|g" \
                                                -e "s|{{REPO_DIR}}|$REPO_DIR|g" \
                                                -e "s|{{HOME}}|$HOME|g" \
                                                -e "s|{{BUN_PATH}}|$BUN_PATH|g")
                    # Skip env vars with unsubstituted placeholders (missing secrets)
                    if echo "$value" | grep -q '{{'; then
                        log_warn "    Skipping env $key (missing secret)"
                        continue
                    fi
                    env_args="$env_args -e $key=$value"
                done < <(echo "$row" | jq -r '.env | to_entries[] | "\(.key)=\(.value)"')
            fi

            log_info "  Adding MCP server: $name"
            # Remove existing server first to update config
            claude mcp remove "$name" -s user 2>/dev/null || true
            if eval "claude mcp add \"$name\" --transport stdio -s user $env_args -- $cmd" 2>/dev/null; then
                log_success "  $name added"
            else
                log_warn "  Failed to add $name"
            fi
        done
        log_success "MCP servers configured"
    else
        log_warn "jq not installed, skipping MCP server auto-install"
        log_info "  Install jq and re-run, or manually add MCP servers"
        add_failure "MCP servers (jq missing)"
    fi
else
    if ! command -v claude &> /dev/null; then
        log_warn "Claude CLI not installed, skipping MCP setup"
        log_info "  After installing Claude CLI, re-run this script"
        add_failure "MCP servers (claude missing)"
    fi
fi

# Step 7: Apply tmux configuration
echo ""
echo "── Step 7: Terminal Configuration ──"

if [ "$PLATFORM" != "windows" ] && command -v tmux &> /dev/null; then
    log_info "Configuring tmux..."
    if [ -f "$REPO_DIR/tmux.conf" ]; then
        # Backup existing config if it exists
        if [ -f "$HOME/.tmux.conf" ]; then
            log_info "Backing up existing ~/.tmux.conf"
            cp "$HOME/.tmux.conf" "$HOME/.tmux.conf.backup.$(date +%s)"
        fi

        # Copy tmux config
        if cp "$REPO_DIR/tmux.conf" "$HOME/.tmux.conf"; then
            log_success "tmux configured: ~/.tmux.conf"
        else
            log_warn "Could not copy tmux config"
            add_failure "tmux config (optional)"
        fi
    fi

    # Install TPM and plugins for session persistence
    log_info "Installing tmux plugins (session persistence)..."
    TMUX_PLUGINS="$HOME/.tmux/plugins"
    mkdir -p "$TMUX_PLUGINS"

    # TPM (Tmux Plugin Manager)
    if [ ! -d "$TMUX_PLUGINS/tpm" ]; then
        if git clone https://github.com/tmux-plugins/tpm "$TMUX_PLUGINS/tpm" 2>/dev/null; then
            log_success "TPM installed"
        else
            log_warn "Could not install TPM"
            add_failure "TPM (optional)"
        fi
    else
        log_success "TPM already installed"
    fi

    # tmux-resurrect (save/restore sessions)
    if [ ! -d "$TMUX_PLUGINS/tmux-resurrect" ]; then
        if git clone https://github.com/tmux-plugins/tmux-resurrect "$TMUX_PLUGINS/tmux-resurrect" 2>/dev/null; then
            log_success "tmux-resurrect installed"
        else
            log_warn "Could not install tmux-resurrect"
            add_failure "tmux-resurrect (optional)"
        fi
    else
        log_success "tmux-resurrect already installed"
    fi

    # tmux-continuum (auto-save/restore)
    if [ ! -d "$TMUX_PLUGINS/tmux-continuum" ]; then
        if git clone https://github.com/tmux-plugins/tmux-continuum "$TMUX_PLUGINS/tmux-continuum" 2>/dev/null; then
            log_success "tmux-continuum installed"
        else
            log_warn "Could not install tmux-continuum"
            add_failure "tmux-continuum (optional)"
        fi
    else
        log_success "tmux-continuum already installed"
    fi
fi

# Step 8: Quota Fetcher Setup (macOS only)
if [ "$PLATFORM" = "mac" ]; then
    echo ""
    echo "── Step 8: Quota Fetcher (macOS) ──"

    if [ -d "$REPO_DIR/quota-fetcher" ]; then
        log_info "Setting up Claude Max quota fetcher..."

        # Install quota-fetcher dependencies
        cd "$REPO_DIR/quota-fetcher"
        if [ -f "package.json" ]; then
            if $BUN_PATH install 2>/dev/null; then
                log_success "Quota fetcher dependencies installed"
            else
                log_warn "Could not install quota-fetcher dependencies"
                add_failure "quota-fetcher deps (optional)"
            fi
        fi
        cd "$CLAUDE_HOME"

        # Set up launchd plist for periodic quota fetching
        PLIST_TEMPLATE="$REPO_DIR/quota-fetcher/com.claude.quota-fetcher.plist.template"
        PLIST_DST="$HOME/Library/LaunchAgents/com.claude.quota-fetcher.plist"

        if [ -f "$PLIST_TEMPLATE" ] && [ -f "$REPO_DIR/quota-fetcher/fetch-quota.ts" ]; then
            # Generate plist from template
            sed -e "s|{{HOME}}|$HOME|g" \
                -e "s|{{CLAUDE_HOME}}|$CLAUDE_HOME|g" \
                "$PLIST_TEMPLATE" > "$PLIST_DST"
            log_success "Quota fetcher launchd plist installed"
            log_info "  To start: launchctl load $PLIST_DST"
            log_info "  First run (login): $BUN_PATH run $CLAUDE_HOME/quota-fetcher/fetch-quota.ts --login"
        else
            log_info "Quota fetcher template not found, skipping launchd setup"
        fi
    else
        log_info "Quota fetcher not found, skipping"
    fi
fi

# Step 9: macOS Performance Tips
if [ "$PLATFORM" = "mac" ]; then
    echo ""
    echo "── Step 9: macOS Performance Tips ──"
    log_info "For faster fullscreen/space switching animations:"
    echo "     System Settings → Accessibility → Display → Reduce motion (ON)"
    log_info "This makes space transitions instant crossfades instead of slow slides."
fi

# Step 10: Obsidian Setup (macOS/Linux)
echo ""
echo "── Step 10: Obsidian Setup ──"

OBSIDIAN_INSTALLED=false

# Check if Obsidian is already installed
if [ "$PLATFORM" = "mac" ]; then
    if [ -d "/Applications/Obsidian.app" ]; then
        log_success "Obsidian already installed"
        OBSIDIAN_INSTALLED=true
    else
        log_info "Installing Obsidian..."
        if brew install --cask obsidian 2>/dev/null; then
            log_success "Obsidian installed"
            OBSIDIAN_INSTALLED=true
        else
            log_warn "Could not install Obsidian via Homebrew"
            log_info "  Install manually from: https://obsidian.md/download"
            add_failure "Obsidian (optional)"
        fi
    fi
elif [ "$PLATFORM" = "linux" ]; then
    if command -v obsidian &> /dev/null || [ -f "/usr/bin/obsidian" ] || [ -f "$HOME/.local/bin/obsidian" ]; then
        log_success "Obsidian already installed"
        OBSIDIAN_INSTALLED=true
    else
        log_info "Installing Obsidian..."
        # Try Flatpak first (most universal)
        if command -v flatpak &> /dev/null; then
            if flatpak install -y flathub md.obsidian.Obsidian 2>/dev/null; then
                log_success "Obsidian installed via Flatpak"
                OBSIDIAN_INSTALLED=true
            fi
        fi
        # Try Snap as fallback
        if [ "$OBSIDIAN_INSTALLED" = false ] && command -v snap &> /dev/null; then
            if sudo snap install obsidian --classic 2>/dev/null; then
                log_success "Obsidian installed via Snap"
                OBSIDIAN_INSTALLED=true
            fi
        fi
        if [ "$OBSIDIAN_INSTALLED" = false ]; then
            log_warn "Could not install Obsidian automatically"
            log_info "  Install manually from: https://obsidian.md/download"
            add_failure "Obsidian (optional)"
        fi
    fi
fi

# Create Obsidian vault directory
OBSIDIAN_VAULT="$HOME/Obsidian/Simon-Personal"
if [ "$OBSIDIAN_INSTALLED" = true ]; then
    if [ ! -d "$OBSIDIAN_VAULT" ]; then
        log_info "Creating Obsidian vault directory..."
        mkdir -p "$OBSIDIAN_VAULT"
        log_success "Vault directory created: $OBSIDIAN_VAULT"
    else
        log_success "Obsidian vault directory exists: $OBSIDIAN_VAULT"
    fi

    # Set up Obsidian Sync config if this is macOS
    if [ "$PLATFORM" = "mac" ]; then
        OBSIDIAN_CONFIG="$HOME/Library/Application Support/obsidian"
        if [ ! -d "$OBSIDIAN_CONFIG" ]; then
            mkdir -p "$OBSIDIAN_CONFIG"
            log_info "Created Obsidian config directory"
        fi

        # Check if Obsidian needs to be launched for initial setup
        if [ ! -f "$OBSIDIAN_CONFIG/obsidian.json" ]; then
            log_info "Obsidian Sync requires initial GUI login."
            log_info "  On headless systems, copy config from another machine:"
            log_info "  1. From primary Mac: scp ~/Library/Application\\ Support/obsidian/obsidian.json user@headless:~/Library/Application\\ Support/obsidian/"
            log_info "  2. Or launch Obsidian via VNC/screen sharing for initial setup"
            add_failure "Obsidian Sync (needs manual config)"
        else
            log_success "Obsidian config exists"
            # Check if sync is configured
            if grep -q "sync" "$OBSIDIAN_CONFIG/obsidian.json" 2>/dev/null; then
                log_success "Obsidian Sync appears to be configured"
            else
                log_warn "Obsidian Sync may not be configured"
                log_info "  Launch Obsidian and enable Sync in settings"
            fi
        fi
    fi
fi

# Step 11: Post-Install Reminders
echo ""
echo "── Step 11: Post-Install ──"

# Remind about Gemini login
if command -v gemini &> /dev/null; then
    log_info "Gemini CLI needs interactive login. Run:"
    echo "    gemini"
    echo "  and follow the prompts to authenticate with Google."
fi

# Summary
echo ""
if [ ${#FAILURES[@]} -eq 0 ]; then
    echo "╔════════════════════════════════════════════╗"
    echo -e "║  ${GREEN}Setup Complete - All Steps Passed!${NC}        ║"
    echo "╚════════════════════════════════════════════╝"
else
    echo "╔════════════════════════════════════════════╗"
    echo -e "║  ${YELLOW}Setup Complete - With Issues${NC}               ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    log_warn "The following steps had issues:"
    for failure in "${FAILURES[@]}"; do
        echo -e "  ${RED}✗${NC} $failure"
    done
fi

echo ""
log_success "Configuration installed from: $REPO_DIR"
log_success "Active Claude profile: $CLAUDE_HOME"
echo ""

# Detect shell profile for reload hint
SHELL_NAME=$(basename "$SHELL")
if [ "$SHELL_NAME" = "zsh" ]; then
    RELOAD_CMD="source ~/.zshrc"
elif [ "$SHELL_NAME" = "bash" ]; then
    RELOAD_CMD="source ~/.bashrc"
else
    RELOAD_CMD="source ~/.profile"
fi

log_info "Next steps:"
echo "  1. Reload shell (or restart terminal):"
echo "     $RELOAD_CMD"
echo "  2. Run 'claude' to start Claude Code"
if command -v gemini &> /dev/null; then
    echo "  3. Run 'gemini' to login to Gemini (for second opinions)"
fi
if [ "$COPILOT_INSTALLED" = true ]; then
    echo "  4. Run 'copilot' to login to GitHub Copilot (for terminal help)"
fi
echo "  5. Use /telegram in Claude to enable Telegram integration"
if [ "$BW_INSTALLED" = true ]; then
    echo ""
    echo "  Vaultwarden setup (one-time):"
    echo "     bw login"
    echo "     bw unlock"
    echo "  Then use /vault in Claude to access credentials"
fi
if [ "$OBSIDIAN_INSTALLED" = true ]; then
    echo ""
    echo "  Obsidian Sync setup (headless systems):"
    echo "     Option A: Copy config from another machine:"
    echo "       scp user@primary:~/Library/Application\\ Support/obsidian/* ~/Library/Application\\ Support/obsidian/"
    echo "     Option B: Use VNC/Screen Sharing for initial GUI setup"
    echo "     Vault location: $OBSIDIAN_VAULT"
fi
echo ""
