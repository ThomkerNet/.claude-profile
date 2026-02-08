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

# MCP DSC mode flag
MCPDSC_MODE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: ./setup.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --help, -h              Show this help message"
            echo "  --mcpdsc <cmd>          MCP DSC operations (list|check|diff|apply-mcp)"
            echo ""
            echo "MCP DSC Commands:"
            echo "  list                    List all defined MCP servers from mcp-servers.json"
            echo "  check                   Check MCP server state without applying changes"
            echo "  diff                    Show what changes would be made to MCP servers"
            echo "  apply-mcp               Apply only the MCP servers step (skip other setup)"
            exit 0
            ;;
        --mcpdsc)
            MCPDSC_MODE="$2"
            shift 2
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
# MCP DSC Functions
# ============================================================================

# Helper: Get list of managed server names from mcp-servers.json
mcp_get_managed_servers() {
    if [ ! -f "$REPO_DIR/mcp-servers.json" ]; then
        echo "Error: mcp-servers.json not found at $REPO_DIR/mcp-servers.json" >&2
        return 1
    fi
    jq -r '.servers[].name' "$REPO_DIR/mcp-servers.json" 2>/dev/null
}

# Helper: Get list of installed server names from ~/.claude.json
mcp_get_installed_servers() {
    local CLAUDE_CONFIG="$HOME/.claude.json"
    if [ -f "$CLAUDE_CONFIG" ]; then
        jq -r '.mcpServers // {} | keys[]' "$CLAUDE_CONFIG" 2>/dev/null
    fi
}

# Helper: Check if MCP server exists in user config
mcp_server_exists() {
    local name="$1"
    local CLAUDE_CONFIG="$HOME/.claude.json"
    if [ -f "$CLAUDE_CONFIG" ]; then
        jq -e --arg n "$name" '.mcpServers[$n] != null' "$CLAUDE_CONFIG" >/dev/null 2>&1
        return $?
    fi
    return 1
}

# Helper: Check if installed MCP server config matches desired state
# Returns 0 if config matches, 1 if drift detected
mcp_server_config_matches() {
    local name="$1"
    local desired_row="$2"
    local CLAUDE_CONFIG="$HOME/.claude.json"

    [ ! -f "$CLAUDE_CONFIG" ] && return 1

    local transport
    transport=$(echo "$desired_row" | jq -r '.transport // "stdio"')
    local installed
    installed=$(jq --arg n "$name" '.mcpServers[$n]' "$CLAUDE_CONFIG" 2>/dev/null)
    [ "$installed" = "null" ] && return 1

    if [ "$transport" = "sse" ]; then
        # SSE: compare URL
        local desired_url installed_url
        desired_url=$(echo "$desired_row" | jq -r '.url')
        installed_url=$(echo "$installed" | jq -r '.url // ""')
        [ "$desired_url" = "$installed_url" ] && return 0 || return 1
    else
        # stdio: compare command + args and env vars
        # Reconstruct desired command string (what claude mcp add receives)
        local desired_cmd installed_cmd
        desired_cmd=$(echo "$desired_row" | jq -r '.command')
        # Installed format: { "command": "npx", "args": ["-y", "pkg"] }
        # Reconstruct: command + " " + args joined by space
        installed_cmd=$(echo "$installed" | jq -r '([.command] + (.args // [])) | join(" ")')
        if [ "$desired_cmd" != "$installed_cmd" ]; then
            return 1
        fi

        # Compare env vars
        # Build desired env with placeholders expanded
        local desired_env installed_env
        desired_env=$(echo "$desired_row" | jq -r '.env // {}' | \
            sed -e "s|{{CLAUDE_HOME}}|$CLAUDE_HOME|g" \
                -e "s|{{REPO_DIR}}|$REPO_DIR|g" \
                -e "s|{{HOME}}|$HOME|g")
        # Filter out entries with unresolved placeholders
        desired_env=$(echo "$desired_env" | jq 'with_entries(select(.value | test("\\{\\{") | not))')
        # Normalize: sort keys
        desired_env=$(echo "$desired_env" | jq -S '.')

        installed_env=$(echo "$installed" | jq -S '.env // {}')

        [ "$desired_env" = "$installed_env" ] && return 0 || return 1
    fi
}

# MCP DSC Command: list
mcpdsc_list() {
    echo "MCP Servers defined in mcp-servers.json:"
    echo ""

    if [ ! -f "$REPO_DIR/mcp-servers.json" ]; then
        echo "Error: mcp-servers.json not found"
        return 1
    fi

    jq -r '.servers[] | "  \(.name) (\(.transport // "stdio")) - \(.description)"' \
        "$REPO_DIR/mcp-servers.json" 2>/dev/null

    echo ""
    echo "Total: $(jq '.servers | length' "$REPO_DIR/mcp-servers.json" 2>/dev/null) servers"
}

# MCP DSC Command: check
mcpdsc_check() {
    echo "Checking MCP server state..."
    echo ""

    local MANAGED_SERVERS=$(mcp_get_managed_servers)
    local INSTALLED_SERVERS=$(mcp_get_installed_servers)

    echo "Defined servers:"
    echo "$MANAGED_SERVERS" | sed 's/^/  ✓ /'
    echo ""

    echo "Installed servers (tkn- prefix only):"
    if [ -z "$INSTALLED_SERVERS" ]; then
        echo "  (none)"
    else
        echo "$INSTALLED_SERVERS" | grep '^tkn-' | sed 's/^/  • /' || echo "  (none with tkn- prefix)"
    fi
    echo ""

    # Check state
    local missing=0
    local extra=0
    local ok=0
    local drifted=0

    # Check for missing/drifted servers
    echo "Status:"
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        local server
        server=$(echo "$row" | jq -r '.name')
        if mcp_server_exists "$server"; then
            if mcp_server_config_matches "$server" "$row"; then
                echo "  ✓ $server (installed)"
                ((ok++)) || true
            else
                echo "  ⚡ $server (installed, config drift)"
                ((drifted++)) || true
            fi
        else
            echo "  ✗ $server (NOT installed)"
            ((missing++)) || true
        fi
    done < <(jq -c '.servers[]' "$REPO_DIR/mcp-servers.json" 2>/dev/null)

    # Check for extra servers
    for installed in $(echo "$INSTALLED_SERVERS" | grep '^tkn-'); do
        if ! echo "$MANAGED_SERVERS" | grep -qx "$installed"; then
            echo "  ⚠ $installed (installed but not in mcp-servers.json)"
            ((extra++)) || true
        fi
    done

    echo ""
    echo "Summary: $ok ok, $drifted drifted, $missing missing, $extra extra"
}

# MCP DSC Command: diff
mcpdsc_diff() {
    echo "MCP Server Changes (dry-run):"
    echo ""

    local changes=0

    # Servers to add (not installed at all)
    local adds=0
    echo "Servers to ADD:"
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        local server transport url
        server=$(echo "$row" | jq -r '.name')
        if ! mcp_server_exists "$server"; then
            transport=$(echo "$row" | jq -r '.transport // "stdio"')
            url=$(echo "$row" | jq -r '.url // ""')
            if [ "$transport" = "sse" ]; then
                echo "  + $server (sse: $url)"
            else
                echo "  + $server (stdio)"
            fi
            ((adds++)) || true
            ((changes++)) || true
        fi
    done < <(jq -c '.servers[]' "$REPO_DIR/mcp-servers.json" 2>/dev/null)
    [ $adds -eq 0 ] && echo "  (none)"

    echo ""

    # Servers with config drift (installed but config doesn't match)
    local drifts=0
    echo "Servers to UPDATE (config drift):"
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        local server
        server=$(echo "$row" | jq -r '.name')
        if mcp_server_exists "$server" && ! mcp_server_config_matches "$server" "$row"; then
            echo "  ~ $server (config drift)"
            ((drifts++)) || true
            ((changes++)) || true
        fi
    done < <(jq -c '.servers[]' "$REPO_DIR/mcp-servers.json" 2>/dev/null)
    [ $drifts -eq 0 ] && echo "  (none)"

    echo ""

    # Servers to remove
    local removes=0
    local MANAGED_SERVERS
    MANAGED_SERVERS=$(mcp_get_managed_servers)
    echo "Servers to REMOVE:"
    for installed in $(mcp_get_installed_servers | grep '^tkn-'); do
        if ! echo "$MANAGED_SERVERS" | grep -qx "$installed"; then
            echo "  - $installed (not in mcp-servers.json)"
            ((removes++)) || true
            ((changes++)) || true
        fi
    done
    [ $removes -eq 0 ] && echo "  (none)"

    echo ""
    if [ $changes -eq 0 ]; then
        echo "No changes needed - all servers in sync"
    else
        echo "Total changes: $changes"
    fi
}

# MCP DSC Command: apply-mcp (extracted from main setup)
mcpdsc_apply() {
    echo "Applying MCP server configuration..."
    echo ""

    # Check prerequisites
    if ! command -v claude &>/dev/null; then
        echo "Error: claude command not found"
        return 1
    fi

    if [ ! -f "$REPO_DIR/mcp-servers.json" ]; then
        echo "Error: mcp-servers.json not found"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        echo "Error: jq command not found"
        return 1
    fi

    # Run the MCP setup (will be called later in the script)
    # For now, just indicate we're in apply mode
    MCPDSC_APPLY_MODE=true
}

# Handle MCP DSC mode
if [ -n "$MCPDSC_MODE" ]; then
    case "$MCPDSC_MODE" in
        list)
            mcpdsc_list
            exit 0
            ;;
        check)
            mcpdsc_check
            exit 0
            ;;
        diff)
            mcpdsc_diff
            exit 0
            ;;
        apply-mcp)
            # Don't exit - continue to main setup but skip non-MCP steps
            MCPDSC_APPLY_MODE=true
            ;;
        *)
            echo "Error: Unknown --mcpdsc command: $MCPDSC_MODE"
            echo "Valid commands: list, check, diff, apply-mcp"
            exit 1
            ;;
    esac
fi

# ============================================================================
# Header
# ============================================================================

if [ -n "$MCPDSC_APPLY_MODE" ]; then
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║   MCP Server DSC Apply                     ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "  Repository: $REPO_DIR"
    echo "  Mode:       MCP servers only"
    echo ""
else
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║   Claude Code Profile Setup (DSC)          ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    echo "  Repository: $REPO_DIR"
    echo "  Target:     $CLAUDE_HOME"
    echo "  Platform:   $DSC_PLATFORM ($DSC_PKG_MANAGER)"
    echo ""
fi

# ============================================================================
# Prerequisites Check
# ============================================================================

if [ -z "$MCPDSC_APPLY_MODE" ]; then
    # Full setup mode - check credentials
    if [ ! -f "$CLAUDE_HOME/.credentials.json" ]; then
        dsc_failed "Claude is not logged in!"
        echo "  Please run 'claude' to login first, then re-run this script"
        echo "  Or use bootstrap.sh which handles this automatically"
        exit 1
    fi
fi

# ============================================================================
# Credential Setup (platform-specific)
# ============================================================================

if [ -z "$MCPDSC_APPLY_MODE" ]; then
    # Skip credential setup in MCP-only mode

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

fi  # End of non-MCP setup steps

# ============================================================================
# Step 5: MCP Servers
# ============================================================================

echo ""
if [ -n "$MCPDSC_APPLY_MODE" ]; then
    echo "── Applying MCP Servers ──"
else
    echo "── Step 5: MCP Servers ──"
fi

if command -v claude &>/dev/null && [ -f "$REPO_DIR/mcp-servers.json" ] && command -v jq &>/dev/null; then
    # User-scoped MCP servers are stored in ~/.claude.json (not ~/.claude/settings.json)
    CLAUDE_CONFIG="$HOME/.claude.json"
    MCP_TIMEOUT=10  # seconds for SSE server connection test

    # Note: Helper functions (mcp_server_exists, mcp_get_managed_servers, mcp_get_installed_servers)
    # are defined in the MCP DSC Functions section above

    # ── Step 11a: Add missing servers ──
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        name=$(echo "$row" | jq -r '.name')
        transport=$(echo "$row" | jq -r '.transport // "stdio"')
        scope=$(echo "$row" | jq -r '.scope // "user"')

        # Idempotent check: skip if server exists and config matches
        is_update=false
        if mcp_server_exists "$name"; then
            if mcp_server_config_matches "$name" "$row"; then
                dsc_unchanged "mcp:$name"
                continue
            fi
            # Drift detected - remove before re-adding
            if ! claude mcp remove "$name" --scope "$scope" 2>/dev/null; then
                dsc_failed "mcp:$name (drift detected, removal failed)"
                continue
            fi
            is_update=true
        fi

        if [ "$transport" = "sse" ]; then
            # SSE transport: connect to remote URL
            url=$(echo "$row" | jq -r '.url')

            # Add SSE server - claude mcp add will validate endpoint connectivity
            mcp_output=$(claude mcp add "$name" --transport sse --scope "$scope" "$url" 2>&1)
            mcp_exit=$?
            if [ $mcp_exit -eq 0 ]; then
                if [ "$is_update" = true ]; then
                    dsc_changed "mcp:$name (updated, sse, scope=$scope)"
                else
                    dsc_changed "mcp:$name (added, sse, scope=$scope)"
                fi
            else
                # Server add failed - endpoint may be unreachable or other error
                echo "    Error: $mcp_output" | head -2 >&2
                dsc_skipped "mcp:$name (failed to add)"
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
                if [ "$is_update" = true ]; then
                    dsc_changed "mcp:$name (updated, scope=$scope)"
                else
                    dsc_changed "mcp:$name (added, scope=$scope)"
                fi
            else
                echo "    Error: $mcp_output" | head -2
                dsc_failed "mcp:$name"
            fi
        fi
    done < <(jq -c '.servers[]' "$REPO_DIR/mcp-servers.json" 2>/dev/null)

    # ── Remove servers not in mcp-servers.json ──
    # Only remove servers that were previously managed by this script (have tkn- prefix)
    # Leave other servers alone (user may have added them manually)
    MANAGED_SERVERS=$(mcp_get_managed_servers)
    for installed in $(mcp_get_installed_servers); do
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

if [ -z "$MCPDSC_APPLY_MODE" ]; then
    # Skip remaining steps in MCP-only mode

echo ""
echo "── Step 6: Secrets ──"

if [ -f "$REPO_DIR/secrets.json" ] && command -v jq &>/dev/null; then
    dsc_unchanged "secrets:secrets.json (found)"
else
    dsc_skipped "secrets (no secrets.json or jq missing)"
fi

fi  # End of non-MCP steps (Step 6+)

# ============================================================================
# Summary
# ============================================================================

dsc_summary

# ============================================================================
# Post-Install Information
# ============================================================================

if [ -z "$MCPDSC_APPLY_MODE" ]; then
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
else
    echo ""
    echo "MCP servers configuration complete."
    echo "Restart Claude sessions to load new servers."
    echo ""
fi
