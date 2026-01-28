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
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: ./setup.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --help, -h              Show this help message"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

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
# Step 1: Configuration Symlinks
# ============================================================================

echo ""
echo "── Step 1: Configuration Symlinks ──"

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
# Step 2: Settings & Templates
# ============================================================================

echo ""
echo "── Step 2: Settings & Templates ──"

# Determine paths for template substitution
if [ "$DSC_PLATFORM" = "windows" ]; then
    STATUSLINE_PATH="$CLAUDE_HOME\\statuslines\\statusline.ps1"
else
    STATUSLINE_PATH="$CLAUDE_HOME/statuslines/statusline.sh"
fi

# Note: User-scoped MCP servers are stored in ~/.claude.json, not ~/.claude/settings.json
# So we can safely overwrite settings.json with the template
ensure_file_template "$REPO_DIR/settings.template.json" "$CLAUDE_HOME/settings.json" \
    "{{CLAUDE_HOME}}=$CLAUDE_HOME" \
    "{{STATUSLINE_PATH}}=$STATUSLINE_PATH"

# ============================================================================
# Step 3: Shell Profile Entries
# ============================================================================

echo ""
echo "── Step 3: Shell Profile ──"

ensure_profile_entry "npm-global" 'export PATH="$HOME/.npm-global/bin:$PATH"'
ensure_profile_entry "local-bin" 'export PATH="$HOME/.local/bin:$PATH"'

# SSH truecolor fix (prevents Claude Code pane flashing over SSH)
ensure_profile_entry "ssh-truecolor" 'if [[ -n "$SSH_CONNECTION" && "$COLORTERM" == "truecolor" ]]; then export TERM=alacritty; fi'

# Apply secrets if available
if [ -f "$REPO_DIR/secrets.json" ] && command -v jq &>/dev/null; then
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
# Step 4: Tools
# ============================================================================

echo ""
echo "── Step 4: Tools ──"

# Spec watcher tools (per-project, not a daemon)
# Make watcher scripts executable for manual/hook use
chmod +x "$REPO_DIR/services/spec-watcher/watcher.sh" 2>/dev/null || true
ensure_directory "$CLAUDE_HOME/.spec-plans"
dsc_unchanged "tools:spec-watcher (available)"

# ============================================================================
# Step 5: MCP Servers
# ============================================================================

echo ""
echo "── Step 5: MCP Servers ──"

if command -v claude &>/dev/null && [ -f "$REPO_DIR/mcp-servers.json" ] && command -v jq &>/dev/null; then
    # User-scoped MCP servers are stored in ~/.claude.json (not ~/.claude/settings.json)
    CLAUDE_CONFIG="$HOME/.claude.json"
    MCP_TIMEOUT=10  # seconds for SSE server connection test

    # Helper: Check if MCP server exists in user config
    mcp_server_exists() {
        local name="$1"
        if [ -f "$CLAUDE_CONFIG" ]; then
            jq -e --arg n "$name" '.mcpServers[$n] != null' "$CLAUDE_CONFIG" >/dev/null 2>&1
            return $?
        fi
        return 1
    }

    # Helper: Get list of managed server names from mcp-servers.json
    get_managed_servers() {
        jq -r '.servers[].name' "$REPO_DIR/mcp-servers.json" 2>/dev/null
    }

    # Helper: Get list of installed server names from ~/.claude.json
    get_installed_servers() {
        if [ -f "$CLAUDE_CONFIG" ]; then
            jq -r '.mcpServers // {} | keys[]' "$CLAUDE_CONFIG" 2>/dev/null
        fi
    }

    # ── Step 11a: Add missing servers ──
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        name=$(echo "$row" | jq -r '.name')
        transport=$(echo "$row" | jq -r '.transport // "stdio"')
        scope=$(echo "$row" | jq -r '.scope // "user"')

        # Idempotent check: skip if server already exists
        if mcp_server_exists "$name"; then
            dsc_unchanged "mcp:$name"
            continue
        fi

        if [ "$transport" = "sse" ]; then
            # SSE transport: connect to remote URL with timeout
            url=$(echo "$row" | jq -r '.url')

            # Test SSE endpoint reachability before adding (with timeout)
            if ! timeout "$MCP_TIMEOUT" curl -sf --max-time "$MCP_TIMEOUT" -o /dev/null "$url" 2>/dev/null; then
                dsc_skipped "mcp:$name (SSE endpoint unreachable: $url)"
                continue
            fi

            mcp_output=$(claude mcp add "$name" --transport sse --scope "$scope" "$url" 2>&1)
            mcp_exit=$?
            if [ $mcp_exit -eq 0 ]; then
                dsc_changed "mcp:$name (added, sse, scope=$scope)"
            else
                echo "    Error: $mcp_output" | head -2
                dsc_failed "mcp:$name"
            fi
        else
            # stdio transport: spawn local process
            cmd=$(echo "$row" | jq -r '.command')

            # Build env args array
            env_args=()
            if echo "$row" | jq -e '.env' >/dev/null 2>&1; then
                while IFS='=' read -r key value; do
                    [ -z "$key" ] && continue
                    value=$(echo "$value" | sed -e "s|{{CLAUDE_HOME}}|$CLAUDE_HOME|g" \
                                                -e "s|{{REPO_DIR}}|$REPO_DIR|g" \
                                                -e "s|{{HOME}}|$HOME|g")
                    # Skip if placeholder not resolved
                    echo "$value" | grep -q '{{' && continue
                    env_args+=("-e" "$key=$value")
                done < <(echo "$row" | jq -r '.env | to_entries[] | "\(.key)=\(.value)"')
            fi

            # Run claude mcp add with proper argument handling
            mcp_output=$(claude mcp add "$name" --transport stdio --scope "$scope" "${env_args[@]}" -- $cmd 2>&1)
            mcp_exit=$?
            if [ $mcp_exit -eq 0 ]; then
                dsc_changed "mcp:$name (added, scope=$scope)"
            else
                echo "    Error: $mcp_output" | head -2
                dsc_failed "mcp:$name"
            fi
        fi
    done < <(jq -c '.servers[]' "$REPO_DIR/mcp-servers.json" 2>/dev/null)

    # ── Remove servers not in mcp-servers.json ──
    # Only remove servers that were previously managed by this script (have tkn- prefix)
    # Leave other servers alone (user may have added them manually)
    MANAGED_SERVERS=$(get_managed_servers)
    for installed in $(get_installed_servers); do
        # Skip if not a tkn- prefixed server (not managed by this profile)
        [[ "$installed" != tkn-* ]] && continue

        # Check if this server is in our managed list
        if echo "$MANAGED_SERVERS" | grep -qx "$installed"; then
            continue  # Server is managed, keep it
        fi

        # Server has tkn- prefix but isn't in mcp-servers.json - remove it
        if claude mcp remove "$installed" --scope user 2>/dev/null; then
            dsc_changed "mcp:$installed (removed - not in mcp-servers.json)"
        else
            dsc_failed "mcp:$installed (removal failed)"
        fi
    done
else
    dsc_skipped "mcp:servers (claude CLI or jq not available)"
fi

# ============================================================================
# Step 6: Secrets Check
# ============================================================================

echo ""
echo "── Step 6: Secrets ──"

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

echo ""
