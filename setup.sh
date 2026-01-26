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

# Parse command line arguments
OBSIDIAN_VAULT_PATH=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --obsidian-vault)
            OBSIDIAN_VAULT_PATH="$2"
            shift 2
            ;;
        --no-obsidian)
            OBSIDIAN_VAULT_PATH="SKIP"
            shift
            ;;
        --help|-h)
            echo "Usage: ./setup.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --obsidian-vault PATH   Override Obsidian vault path (default: from secrets.json)"
            echo "  --no-obsidian           Skip Obsidian git sync setup"
            echo "  --help, -h              Show this help message"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Load Obsidian vault path from secrets.json if not specified
if [ -z "$OBSIDIAN_VAULT_PATH" ] && [ -f "$REPO_DIR/secrets.json" ] && command -v jq &>/dev/null; then
    OBSIDIAN_VAULT_PATH=$(jq -r '.obsidian.vault_path // empty' "$REPO_DIR/secrets.json")
    # Expand ~ to $HOME
    OBSIDIAN_VAULT_PATH="${OBSIDIAN_VAULT_PATH/#\~/$HOME}"
fi

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
# Credential Setup (platform-specific)
# ============================================================================

HAVE_ADMIN=false
ADMIN_USER=""
BREW_ADMIN=""
CURRENT_USER="$(whoami)"

if [ "$DSC_PLATFORM" = "mac" ]; then
    # ── macOS: Homebrew Single-Owner Model ──
    # Homebrew is owned by one user (e.g., macmini-admin)
    # Other users run brew commands via su + expect (macOS su needs TTY)

    if [ -d "/opt/homebrew" ]; then
        BREW_OWNER=$(stat -f '%Su' /opt/homebrew 2>/dev/null || echo "")

        if [ "$BREW_OWNER" = "$CURRENT_USER" ]; then
            # Current user owns Homebrew - direct access
            dsc_unchanged "homebrew:owner ($CURRENT_USER)"
        elif [ -n "$BREW_OWNER" ]; then
            # Different owner - need to authenticate as that user
            echo ""
            echo "── Homebrew Access ──"
            echo "  Homebrew is owned by: $BREW_OWNER"

            # Check if credentials already provided via environment
            if [ -n "${BREW_PASS:-}" ]; then
                echo "  Using credentials from environment."
            else
                echo "  You ($CURRENT_USER) will need their credentials for brew commands."
                echo ""
                read -p "  Enter password for $BREW_OWNER (or press Enter to skip brew installs): " -s BREW_PASS
                echo ""
            fi

            if [ -n "$BREW_PASS" ]; then
                # Test authentication using expect heredoc (hides password from ps)
                # Uses timeout and exit code validation for robustness
                export BREW_OWNER BREW_PASS
                auth_result=$(expect <<'EXPECT_SCRIPT' 2>&1
                    set timeout 30
                    log_user 1
                    spawn su - $env(BREW_OWNER) -c "echo AUTH_OK"
                    expect {
                        "Password:" {
                            log_user 0
                            send "$env(BREW_PASS)\r"
                            log_user 1
                            expect {
                                "AUTH_OK" { exit 0 }
                                "Sorry" { exit 1 }
                                timeout { exit 2 }
                                eof { exit 1 }
                            }
                        }
                        timeout { exit 2 }
                        eof { exit 1 }
                    }
EXPECT_SCRIPT
                )
                auth_exit=$?

                if [ $auth_exit -eq 0 ] && echo "$auth_result" | grep -q "AUTH_OK"; then
                    BREW_ADMIN="$BREW_OWNER"
                    # BREW_PASS already exported for dsc_run_brew
                    dsc_changed "homebrew:access (via $BREW_OWNER)"
                else
                    echo "  ⚠️  Authentication failed (exit code: $auth_exit)"
                    dsc_skipped "homebrew:access (auth failed)"
                    unset BREW_PASS
                fi
            else
                dsc_skipped "homebrew:access (skipped)"
            fi
            echo ""
        fi
    fi

elif [ "$DSC_PLATFORM" = "linux" ]; then
    # ── Linux: sudo/su for package managers ──
    needs_admin=false
    [ ! -x "$(command -v jq)" ] && needs_admin=true
    [ ! -x "$(command -v tmux)" ] && needs_admin=true

    if [ "$needs_admin" = true ]; then
        echo ""
        echo "── Admin Access Required ──"
        echo "  Some packages need to be installed."
        echo ""

        if sudo -n true 2>/dev/null; then
            HAVE_ADMIN=true
            dsc_unchanged "admin:sudo (already authenticated)"
        elif sudo -v 2>/dev/null; then
            HAVE_ADMIN=true
            dsc_changed "admin:sudo (credentials cached)"
            (while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done) &
        else
            echo "  sudo not available. Enter admin username (or Enter to skip):"
            read -p "  Admin username: " ADMIN_USER

            if [ -n "$ADMIN_USER" ]; then
                if su - "$ADMIN_USER" -c "echo 'ok'" 2>/dev/null | grep -q "ok"; then
                    HAVE_ADMIN=true
                    dsc_changed "admin:su (using $ADMIN_USER)"
                else
                    dsc_skipped "admin:su (auth failed)"
                fi
            else
                dsc_skipped "admin:access (skipped)"
            fi
        fi
        echo ""
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

# GitHub Copilot CLI (used for AI peer reviews)
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

# Git-LFS (for Obsidian vault binary files)
if command -v git-lfs &>/dev/null; then
    dsc_unchanged "brew:git-lfs"
else
    if [ "$DSC_PLATFORM" = "mac" ] && command -v brew &>/dev/null; then
        echo -e "  ${_BLUE}Installing git-lfs...${_NC}"
        if dsc_run_brew install git-lfs &>/dev/null; then
            git lfs install &>/dev/null
            dsc_changed "brew:git-lfs (installed)"
        else
            dsc_failed "brew:git-lfs"
        fi
    elif [ "$DSC_PLATFORM" = "linux" ]; then
        # Try package manager
        if [ "$DSC_PKG_MANAGER" = "apt" ]; then
            if sudo apt-get install -y git-lfs &>/dev/null; then
                git lfs install &>/dev/null
                dsc_changed "apt:git-lfs (installed)"
            else
                dsc_failed "apt:git-lfs"
            fi
        else
            dsc_skipped "git-lfs (manual install needed)"
        fi
    fi
fi

# Glances (system monitoring)
if [ "$DSC_PLATFORM" = "mac" ]; then
    if command -v glances &>/dev/null; then
        dsc_unchanged "brew:glances"
    elif command -v brew &>/dev/null; then
        echo -e "  ${_BLUE}Installing glances via Homebrew...${_NC}"
        if dsc_run_brew install glances &>/dev/null; then
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
ensure_symlink "$REPO_DIR/output" "$CLAUDE_HOME/output" "output/"
ensure_symlink "$REPO_DIR/plugins" "$CLAUDE_HOME/plugins" "plugins/"
ensure_symlink "$REPO_DIR/docs" "$CLAUDE_HOME/docs" "docs/"
ensure_symlink "$REPO_DIR/configs" "$CLAUDE_HOME/configs" "configs/"
ensure_symlink "$REPO_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md" "CLAUDE.md"
[ -f "$REPO_DIR/secrets.json" ] && ensure_symlink "$REPO_DIR/secrets.json" "$CLAUDE_HOME/secrets.json" "secrets.json"

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

# SSH truecolor fix (prevents Claude Code pane flashing over SSH)
ensure_profile_entry "ssh-truecolor" 'if [[ -n "$SSH_CONNECTION" && "$COLORTERM" == "truecolor" ]]; then export TERM=alacritty; fi'

# Apply secrets if available
if [ -f "$REPO_DIR/secrets.json" ] && command -v jq &>/dev/null; then
    FIRECRAWL_KEY=$(jq -r '.api_keys.firecrawl // empty' "$REPO_DIR/secrets.json")
    if [ -n "$FIRECRAWL_KEY" ] && [ "$FIRECRAWL_KEY" != "YOUR_FIRECRAWL_API_KEY" ]; then
        ensure_profile_entry "FIRECRAWL_API_KEY" "export FIRECRAWL_API_KEY='$FIRECRAWL_KEY'"
    fi

    # LiteLLM proxy config for AI peer review
    LITELLM_URL=$(jq -r '.litellm.base_url // empty' "$REPO_DIR/secrets.json")
    LITELLM_KEY=$(jq -r '.litellm.api_key // empty' "$REPO_DIR/secrets.json")
    if [ -n "$LITELLM_URL" ]; then
        ensure_profile_entry "LITELLM_BASE_URL" "export LITELLM_BASE_URL='$LITELLM_URL'"
    fi
    if [ -n "$LITELLM_KEY" ]; then
        ensure_profile_entry "LITELLM_API_KEY" "export LITELLM_API_KEY='$LITELLM_KEY'"
    fi
fi

# ============================================================================
# Step 8: Services (launchd/systemd)
# ============================================================================

echo ""
echo "── Step 8: Background Services ──"

if [ "$DSC_PLATFORM" = "mac" ]; then
    ensure_directory "$HOME/Library/LaunchAgents"

    # Glances monitoring service (plist only - manual load recommended)
    if [ -f "$REPO_DIR/services/com.claude.glances.plist" ]; then
        GLANCES_PLIST="$HOME/Library/LaunchAgents/com.claude.glances.plist"
        ensure_file_template "$REPO_DIR/services/com.claude.glances.plist" "$GLANCES_PLIST" \
            "{{HOME}}=$HOME" \
            "{{CLAUDE_HOME}}=$CLAUDE_HOME"

        # Check if service is running (don't try to load - launchctl has issues in some contexts)
        if launchctl list 2>/dev/null | grep -q "com.claude.glances"; then
            dsc_unchanged "service:com.claude.glances (running)"
        else
            dsc_info "service:com.claude.glances plist installed. Load manually: launchctl load $GLANCES_PLIST"
            dsc_unchanged "service:com.claude.glances (plist ready)"
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

    # Enable linger for user services to run after logout
    ensure_user_linger

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
# Step 8b: Obsidian Git Sync (Optional)
# ============================================================================

if [ -n "$OBSIDIAN_VAULT_PATH" ] && [ "$OBSIDIAN_VAULT_PATH" != "SKIP" ]; then
    echo ""
    echo "── Step 8b: Obsidian Git Sync ──"

    if [ ! -d "$OBSIDIAN_VAULT_PATH" ]; then
        dsc_failed "obsidian-vault (directory not found: $OBSIDIAN_VAULT_PATH)"
    else
        # Load credentials from secrets.json and PAT from Bitwarden
        OBSIDIAN_GIT_REMOTE=""
        if [ -f "$REPO_DIR/secrets.json" ] && command -v jq &>/dev/null; then
            OBSIDIAN_REPO=$(jq -r '.obsidian.github_repo // empty' "$REPO_DIR/secrets.json")
            OBSIDIAN_USER=$(jq -r '.obsidian.github_user // empty' "$REPO_DIR/secrets.json")
            OBSIDIAN_BW_ITEM=$(jq -r '.obsidian.bitwarden_item // empty' "$REPO_DIR/secrets.json")

            if [ -n "$OBSIDIAN_REPO" ] && [ -n "$OBSIDIAN_USER" ]; then
                # Try to get PAT from Bitwarden
                OBSIDIAN_PAT=""
                BW_CMD=$(command -v bw || echo "$HOME/.npm-global/bin/bw")

                if [ -x "$BW_CMD" ] && [ -n "$OBSIDIAN_BW_ITEM" ]; then
                    # Check if Bitwarden is unlocked
                    BW_STATUS=$($BW_CMD status 2>/dev/null | jq -r '.status // "unauthenticated"')

                    if [ "$BW_STATUS" = "unlocked" ]; then
                        OBSIDIAN_PAT=$($BW_CMD get password "$OBSIDIAN_BW_ITEM" 2>/dev/null)
                        if [ -n "$OBSIDIAN_PAT" ]; then
                            dsc_unchanged "config:obsidian-pat (from Bitwarden)"
                        fi
                    elif [ "$BW_STATUS" = "locked" ]; then
                        echo ""
                        echo -e "  ${_YELLOW}Bitwarden is locked. Unlock to configure Obsidian git sync:${_NC}"
                        echo "    bw unlock"
                        echo "    export BW_SESSION=<session>"
                        echo ""
                        read -p "  Press Enter after unlocking (or Enter to skip Obsidian setup): " -r

                        # Check again after prompt
                        BW_STATUS=$($BW_CMD status 2>/dev/null | jq -r '.status // "unauthenticated"')
                        if [ "$BW_STATUS" = "unlocked" ]; then
                            OBSIDIAN_PAT=$($BW_CMD get password "$OBSIDIAN_BW_ITEM" 2>/dev/null)
                            if [ -n "$OBSIDIAN_PAT" ]; then
                                dsc_changed "config:obsidian-pat (from Bitwarden)"
                            fi
                        fi
                    else
                        dsc_info "Bitwarden not logged in - run 'bw login' first for Obsidian setup"
                    fi
                fi

                if [ -n "$OBSIDIAN_PAT" ]; then
                    OBSIDIAN_GIT_REMOTE="https://${OBSIDIAN_USER}:${OBSIDIAN_PAT}@github.com/${OBSIDIAN_USER}/${OBSIDIAN_REPO}.git"
                else
                    dsc_skipped "config:obsidian-credentials (Bitwarden locked or PAT not found)"
                fi
            fi
        fi

        # Initialize git repo if needed
        if [ ! -d "$OBSIDIAN_VAULT_PATH/.git" ]; then
            if [ -z "$OBSIDIAN_GIT_REMOTE" ]; then
                dsc_failed "obsidian-vault (not a git repo and no credentials in secrets.json)"
                echo "  Add to secrets.json: { \"obsidian\": { \"github_user\": \"...\", \"github_repo\": \"...\", \"github_pat\": \"...\" } }"
            else
                echo -e "  ${_BLUE}Initializing Obsidian vault as git repo...${_NC}"
                cd "$OBSIDIAN_VAULT_PATH"

                # Initialize git and LFS
                git init &>/dev/null
                git lfs install &>/dev/null 2>&1 || true
                dsc_changed "git:init (initialized)"

                # Create .gitattributes for LFS
                if [ ! -f ".gitattributes" ]; then
                    cat > .gitattributes << 'GITATTR'
# Git LFS - Track large binary files
*.pdf filter=lfs diff=lfs merge=lfs -text
*.png filter=lfs diff=lfs merge=lfs -text
*.jpg filter=lfs diff=lfs merge=lfs -text
*.jpeg filter=lfs diff=lfs merge=lfs -text
*.gif filter=lfs diff=lfs merge=lfs -text
*.bmp filter=lfs diff=lfs merge=lfs -text
*.webp filter=lfs diff=lfs merge=lfs -text
*.mov filter=lfs diff=lfs merge=lfs -text
*.mp4 filter=lfs diff=lfs merge=lfs -text
*.mp3 filter=lfs diff=lfs merge=lfs -text
*.zip filter=lfs diff=lfs merge=lfs -text
*.pptx filter=lfs diff=lfs merge=lfs -text
*.docx filter=lfs diff=lfs merge=lfs -text
*.xlsx filter=lfs diff=lfs merge=lfs -text
GITATTR
                    dsc_changed "file:.gitattributes (created)"
                fi

                # Create .gitignore
                if [ ! -f ".gitignore" ]; then
                    cat > .gitignore << 'GITIGN'
# Obsidian workspace/cache (device-specific)
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/plugins/*/data.json
.obsidian/.obsidian.vimrc

# System files
.trash/
.DS_Store
Thumbs.db
GITIGN
                    dsc_changed "file:.gitignore (created)"
                fi

                # Configure remote
                git remote add origin "$OBSIDIAN_GIT_REMOTE" 2>/dev/null || \
                    git remote set-url origin "$OBSIDIAN_GIT_REMOTE"
                dsc_changed "git:remote (configured)"

                # Initial commit and push
                git add -A
                if git commit -m "Initial vault commit from $(hostname -s)" --no-gpg-sign &>/dev/null; then
                    dsc_changed "git:commit (initial)"
                    if git push -u origin main &>/dev/null 2>&1 || git push -u origin master &>/dev/null 2>&1; then
                        dsc_changed "git:push (initial)"
                    else
                        dsc_info "git:push failed - may need to create repo on GitHub first"
                    fi
                else
                    dsc_info "git:commit (no changes or already committed)"
                fi
                cd "$CLAUDE_HOME"
            fi
        else
            dsc_unchanged "git:repo (already initialized)"

            # Update remote URL if credentials available and different
            if [ -n "$OBSIDIAN_GIT_REMOTE" ]; then
                cd "$OBSIDIAN_VAULT_PATH"
                current_remote=$(git remote get-url origin 2>/dev/null || echo "")
                if [ "$current_remote" != "$OBSIDIAN_GIT_REMOTE" ]; then
                    git remote set-url origin "$OBSIDIAN_GIT_REMOTE"
                    dsc_changed "git:remote (updated)"
                else
                    dsc_unchanged "git:remote"
                fi
                cd "$CLAUDE_HOME"
            fi
        fi

        # Configure sync service (only if vault is now a git repo)
        if [ -d "$OBSIDIAN_VAULT_PATH/.git" ]; then
            SYNC_SCRIPT="$CLAUDE_HOME/services/obsidian-git-sync/sync.sh"

            if [ -f "$SYNC_SCRIPT" ] || [ -L "$SYNC_SCRIPT" ]; then
                chmod +x "$SYNC_SCRIPT" 2>/dev/null || true
                dsc_unchanged "script:obsidian-sync.sh"

                # Install service (platform-specific)
                if [ "$DSC_PLATFORM" = "mac" ]; then
                    OBSIDIAN_PLIST="$HOME/Library/LaunchAgents/com.claude.obsidian-git-sync.plist"

                    if [ -f "$REPO_DIR/services/obsidian-git-sync/com.claude.obsidian-git-sync.plist.template" ]; then
                        ensure_file_template "$REPO_DIR/services/obsidian-git-sync/com.claude.obsidian-git-sync.plist.template" \
                            "$OBSIDIAN_PLIST" \
                            "{{HOME}}=$HOME" \
                            "{{CLAUDE_HOME}}=$CLAUDE_HOME" \
                            "{{OBSIDIAN_VAULT_PATH}}=$OBSIDIAN_VAULT_PATH"

                        if launchctl list 2>/dev/null | grep -q "com.claude.obsidian-git-sync"; then
                            dsc_unchanged "service:obsidian-git-sync (running)"
                        else
                            if launchctl load "$OBSIDIAN_PLIST" 2>/dev/null; then
                                dsc_changed "service:obsidian-git-sync (started)"
                            else
                                dsc_info "service:obsidian-git-sync - load manually: launchctl load $OBSIDIAN_PLIST"
                                dsc_unchanged "service:obsidian-git-sync (plist ready)"
                            fi
                        fi
                    else
                        dsc_failed "obsidian-git-sync (plist template not found)"
                    fi

                elif [ "$DSC_PLATFORM" = "linux" ]; then
                    # systemd user service + timer
                    SERVICE_DIR="$HOME/.config/systemd/user"
                    ensure_directory "$SERVICE_DIR"

                    # Enable linger so user services run after logout
                    ensure_user_linger

                    SERVICE_TEMPLATE="$REPO_DIR/services/obsidian-git-sync/obsidian-git-sync.service.template"
                    TIMER_TEMPLATE="$REPO_DIR/services/obsidian-git-sync/obsidian-git-sync.timer.template"

                    if [ -f "$SERVICE_TEMPLATE" ] && [ -f "$TIMER_TEMPLATE" ]; then
                        # Generate and install service file
                        ensure_file_template "$SERVICE_TEMPLATE" \
                            "$SERVICE_DIR/obsidian-git-sync.service" \
                            "{{HOME}}=$HOME" \
                            "{{CLAUDE_HOME}}=$CLAUDE_HOME" \
                            "{{OBSIDIAN_VAULT_PATH}}=$OBSIDIAN_VAULT_PATH"

                        # Generate and install timer file (no substitutions needed)
                        ensure_file_copy "$TIMER_TEMPLATE" "$SERVICE_DIR/obsidian-git-sync.timer" "obsidian-git-sync.timer"

                        # Reload systemd
                        systemctl --user daemon-reload 2>/dev/null || true

                        # Enable and start timer
                        if systemctl --user is-active obsidian-git-sync.timer &>/dev/null; then
                            dsc_unchanged "service:obsidian-git-sync.timer (running)"
                        elif systemctl --user is-enabled obsidian-git-sync.timer &>/dev/null; then
                            if systemctl --user start obsidian-git-sync.timer 2>/dev/null; then
                                dsc_changed "service:obsidian-git-sync.timer (started)"
                            else
                                dsc_info "service:obsidian-git-sync.timer - start manually: systemctl --user start obsidian-git-sync.timer"
                            fi
                        else
                            if systemctl --user enable --now obsidian-git-sync.timer 2>/dev/null; then
                                dsc_changed "service:obsidian-git-sync.timer (enabled and started)"
                            else
                                dsc_info "service:obsidian-git-sync.timer - enable manually: systemctl --user enable --now obsidian-git-sync.timer"
                                dsc_unchanged "service:obsidian-git-sync (unit files installed)"
                            fi
                        fi
                    else
                        dsc_failed "obsidian-git-sync (systemd templates not found)"
                    fi
                else
                    dsc_skipped "service:obsidian-git-sync (unsupported platform)"
                fi
            else
                dsc_failed "obsidian-git-sync (sync.sh not found)"
            fi
        fi
    fi
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

# Obsidian (optional - not required if using git sync only)
if [ "$DSC_PLATFORM" = "mac" ]; then
    if [ -d "/Applications/Obsidian.app" ]; then
        dsc_unchanged "app:Obsidian (optional, installed)"
    else
        # Don't auto-install - Obsidian.app is optional with git sync
        dsc_skipped "app:Obsidian (not required with git sync)"
    fi
elif [ "$DSC_PLATFORM" = "linux" ]; then
    # Check various Obsidian installation methods on Linux
    if command -v obsidian &>/dev/null; then
        dsc_unchanged "app:Obsidian (optional, installed)"
    elif [ -d "/opt/Obsidian" ] || [ -f "$HOME/Applications/Obsidian.AppImage" ]; then
        dsc_unchanged "app:Obsidian (optional, installed via AppImage)"
    elif snap list obsidian &>/dev/null 2>&1; then
        dsc_unchanged "app:Obsidian (optional, installed via snap)"
    elif flatpak list --app 2>/dev/null | grep -qi obsidian; then
        dsc_unchanged "app:Obsidian (optional, installed via flatpak)"
    else
        dsc_skipped "app:Obsidian (not required with git sync - install via AppImage/snap/flatpak if needed)"
    fi
fi

# ============================================================================
# Step 11: MCP Servers (Interactive)
# ============================================================================

echo ""
echo "── Step 11: MCP Servers ──"

if command -v claude &>/dev/null && [ -f "$REPO_DIR/mcp-servers.json" ] && command -v jq &>/dev/null; then
    # Get list of currently installed MCP servers (parse name from "name: command" format)
    INSTALLED_SERVERS=$(claude mcp list 2>/dev/null | grep -E "^[a-z].*:" | cut -d: -f1 || echo "")

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

        # Install MCP server (--scope user for user-level config)
        if eval "claude mcp add \"$name\" --transport stdio --scope user $env_args -- $cmd" &>/dev/null; then
            dsc_changed "mcp:$name (added)"
        else
            dsc_failed "mcp:$name"
        fi
    done
else
    dsc_skipped "mcp:servers (claude CLI or jq not available)"
fi

# ============================================================================
# Step 12: Secrets Check
# ============================================================================

echo ""
echo "── Step 12: Secrets ──"

if [ -f "$REPO_DIR/secrets.json" ] && command -v jq &>/dev/null; then
    dsc_unchanged "secrets:secrets.json (found)"
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
echo "  3. Run './setup-repos.sh' to clone organization repos to ~/git-bnx"
command -v bw &>/dev/null && echo "  4. Run 'bw login' for Vaultwarden access"

echo ""
