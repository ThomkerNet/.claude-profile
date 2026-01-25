#!/bin/bash
#
# DSC-Style Resource Library for Claude Profile Setup
# Provides idempotent, declarative resource management
#
# Pattern: Test-Get-Set
# - Test: Check if resource is in desired state
# - Get: Return current state
# - Set: Make changes only if needed
#
# Usage: source this file, then call ensure_* functions
#

# ============================================================================
# Configuration & State Tracking
# ============================================================================

DSC_CHANGES=0
DSC_UNCHANGED=0
DSC_FAILED=0
DSC_FAILURES=()
DSC_VERBOSE=${DSC_VERBOSE:-false}

# Colors
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
_BLUE='\033[0;34m'
_NC='\033[0m'

# Logging functions (use || true to prevent set -e exit when incrementing from 0)
dsc_changed()   { echo -e "${_GREEN}[changed]${_NC} $1"; ((DSC_CHANGES++)) || true; }
dsc_unchanged() { echo -e "${_BLUE}[ok]${_NC} $1"; ((DSC_UNCHANGED++)) || true; }
dsc_failed()    { echo -e "${_RED}[failed]${_NC} $1"; ((DSC_FAILED++)) || true; DSC_FAILURES+=("$1"); }
dsc_skipped()   { echo -e "${_YELLOW}[skipped]${_NC} $1"; }
dsc_info()      { [ "$DSC_VERBOSE" = true ] && echo -e "${_BLUE}[info]${_NC} $1" || true; }

# ============================================================================
# Platform Detection
# ============================================================================

detect_platform() {
    case "$(uname -s)" in
        Darwin*)  echo "mac" ;;
        Linux*)   echo "linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

detect_pkg_manager() {
    case "$(detect_platform)" in
        mac) echo "brew" ;;
        linux)
            if command -v apt-get &>/dev/null; then echo "apt"
            elif command -v dnf &>/dev/null; then echo "dnf"
            elif command -v yum &>/dev/null; then echo "yum"
            elif command -v pacman &>/dev/null; then echo "pacman"
            else echo "unknown"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

DSC_PLATFORM=$(detect_platform)
DSC_PKG_MANAGER=$(detect_pkg_manager)

# ============================================================================
# Privileged Command Execution
# ============================================================================

# dsc_run_privileged <command>
# Runs a command with admin privileges (uses HAVE_ADMIN/ADMIN_USER set by setup.sh)
dsc_run_privileged() {
    local cmd="$1"

    # Check if we have admin access (set by setup.sh after sourcing this file)
    if [ "${HAVE_ADMIN:-false}" = true ]; then
        if [ -n "${ADMIN_USER:-}" ]; then
            # Use su to run as admin user
            su - "$ADMIN_USER" -c "$cmd" 2>/dev/null
            return $?
        else
            # Current user has sudo access
            sudo sh -c "$cmd" 2>/dev/null
            return $?
        fi
    else
        # No admin access - try sudo anyway (might prompt or fail)
        sudo sh -c "$cmd" 2>/dev/null
        return $?
    fi
}

# ============================================================================
# Homebrew Execution (single-owner model)
# ============================================================================

# dsc_run_brew <args...>
# Runs brew command - via BREW_ADMIN user if set, otherwise directly
# Set BREW_ADMIN and BREW_PASS in setup.sh when current user doesn't own Homebrew
# Uses expect heredoc (hides password from ps) with timeout for robustness
dsc_run_brew() {
    local args="$*"

    if [ -n "${BREW_ADMIN:-}" ] && [ -n "${BREW_PASS:-}" ]; then
        # Run as Homebrew owner via su + expect heredoc (hides password from ps)
        export BREW_ARGS="$args"
        expect <<'EXPECT_BREW' 2>/dev/null
            set timeout 300
            log_user 0
            spawn su - $env(BREW_ADMIN) -c "brew $env(BREW_ARGS)"
            expect {
                "Password:" {
                    send "$env(BREW_PASS)\r"
                    log_user 1
                    expect {
                        eof {
                            catch wait result
                            exit [lindex $result 3]
                        }
                        timeout { exit 124 }
                    }
                }
                timeout { exit 124 }
                eof { exit 1 }
            }
EXPECT_BREW
        return $?
    elif [ -n "${BREW_ADMIN:-}" ]; then
        # BREW_ADMIN set but no password - try without (will likely fail)
        su - "$BREW_ADMIN" -c "brew $args" 2>/dev/null
        return $?
    else
        # Current user owns Homebrew
        brew $args
        return $?
    fi
}

# ============================================================================
# Resource: Package
# ============================================================================

# ensure_package <name> [brew_name] [apt_name]
# Ensures a system package is installed
ensure_package() {
    local name=$1
    local brew_name=${2:-$1}
    local apt_name=${3:-$1}

    # Test: Is package already available?
    if command -v "$name" &>/dev/null; then
        dsc_unchanged "package:$name (already installed)"
        return 0
    fi

    # Set: Install package
    local success=false
    case "$DSC_PKG_MANAGER" in
        brew)
            # Use dsc_run_brew for single-owner homebrew model
            if dsc_run_brew install "$brew_name" &>/dev/null; then
                success=true
            fi
            ;;
        apt)
            if dsc_run_privileged "apt-get install -y -qq $apt_name"; then
                success=true
            fi
            ;;
        dnf)
            if dsc_run_privileged "dnf install -y -q $apt_name"; then
                success=true
            fi
            ;;
        yum)
            if dsc_run_privileged "yum install -y -q $apt_name"; then
                success=true
            fi
            ;;
        pacman)
            if dsc_run_privileged "pacman -S --noconfirm $apt_name"; then
                success=true
            fi
            ;;
        *)
            dsc_failed "package:$name (unknown package manager)"
            return 0
            ;;
    esac

    if [ "$success" = true ] && command -v "$name" &>/dev/null; then
        dsc_changed "package:$name (installed)"
        return 0
    fi

    dsc_failed "package:$name (install failed)"
    # Return 0 to continue script execution (failure is logged)
    return 0
}

# ============================================================================
# Resource: NPM Package
# ============================================================================

# ensure_npm_package <package_name> <command_name>
# Ensures an npm package is globally installed
ensure_npm_package() {
    local pkg=$1
    local cmd=${2:-$1}
    local npm_prefix="${HOME}/.npm-global"

    # Test: Is command available?
    if command -v "$cmd" &>/dev/null || [ -f "$npm_prefix/bin/$cmd" ]; then
        dsc_unchanged "npm:$pkg (already installed)"
        return 0
    fi

    # Set: Install via npm
    if ! command -v npm &>/dev/null; then
        dsc_failed "npm:$pkg (npm not available)"
        return 0  # Continue script execution
    fi

    echo -e "  ${_BLUE}Installing $pkg...${_NC}"
    if npm install -g "$pkg" 2>&1 | grep -E "added|packages" | head -2 | sed 's/^/    /'; then
        if command -v "$cmd" &>/dev/null || [ -f "$npm_prefix/bin/$cmd" ]; then
            dsc_changed "npm:$pkg (installed)"
            return 0
        fi
    fi

    dsc_failed "npm:$pkg (install failed)"
    return 0  # Continue script execution
}

# ============================================================================
# Resource: Pip Package
# ============================================================================

# ensure_pip_package <package_name> <command_name>
ensure_pip_package() {
    local pkg=$1
    local cmd=${2:-$1}
    local local_bin="${HOME}/.local/bin"

    # Test: Is command available?
    if command -v "$cmd" &>/dev/null || [ -f "$local_bin/$cmd" ]; then
        dsc_unchanged "pip:$pkg (already installed)"
        return 0
    fi

    # Set: Install via pip
    local pip_cmd=""
    if command -v pip3 &>/dev/null; then pip_cmd="pip3"
    elif command -v pip &>/dev/null; then pip_cmd="pip"
    else
        dsc_failed "pip:$pkg (pip not available)"
        return 0  # Continue script execution
    fi

    echo -e "  ${_BLUE}Installing $pkg...${_NC}"
    if $pip_cmd install --user "$pkg" 2>&1 | grep -E "Installing|Successfully" | head -2 | sed 's/^/    /'; then
        # Add local bin to PATH
        if [ -d "$local_bin" ] && [[ ":$PATH:" != *":$local_bin:"* ]]; then
            export PATH="$local_bin:$PATH"
        fi
        if command -v "$cmd" &>/dev/null || [ -f "$local_bin/$cmd" ]; then
            dsc_changed "pip:$pkg (installed)"
            return 0
        fi
    fi

    dsc_failed "pip:$pkg (install failed)"
    return 0  # Continue script execution
}

# ============================================================================
# Resource: Symlink
# ============================================================================

# ensure_symlink <source> <target> [description]
# Ensures a symlink exists pointing to the correct target
ensure_symlink() {
    local source=$1
    local target=$2
    local desc=${3:-$(basename "$target")}

    # Test: Does source exist?
    if [ ! -e "$source" ]; then
        dsc_skipped "symlink:$desc (source missing: $source)"
        return 1
    fi

    # Test: Is symlink correct?
    if [ -L "$target" ]; then
        local current_target
        current_target=$(readlink "$target")
        if [ "$current_target" = "$source" ]; then
            dsc_unchanged "symlink:$desc"
            return 0
        fi
        # Symlink exists but points elsewhere - remove it
        rm "$target"
    elif [ -e "$target" ]; then
        # Target exists but is not a symlink - backup
        local backup="${target}.backup.$(date +%s)"
        mv "$target" "$backup"
        dsc_info "Backed up existing $desc to $backup"
    fi

    # Set: Create symlink
    if ln -s "$source" "$target"; then
        dsc_changed "symlink:$desc"
        return 0
    fi

    dsc_failed "symlink:$desc"
    return 1
}

# ============================================================================
# Resource: Directory
# ============================================================================

# ensure_directory <path> [mode]
ensure_directory() {
    local path=$1
    local mode=${2:-755}

    # Test: Does directory exist?
    if [ -d "$path" ]; then
        dsc_unchanged "directory:$path"
        return 0
    fi

    # Set: Create directory
    if mkdir -p "$path" && chmod "$mode" "$path"; then
        dsc_changed "directory:$path (created)"
        return 0
    fi

    dsc_failed "directory:$path"
    return 1
}

# ============================================================================
# Resource: File Copy
# ============================================================================

# ensure_file_copy <source> <target> [description]
# Copies file only if content differs
ensure_file_copy() {
    local source=$1
    local target=$2
    local desc=${3:-$(basename "$target")}

    # Test: Does source exist?
    if [ ! -f "$source" ]; then
        dsc_skipped "file:$desc (source missing)"
        return 1
    fi

    # Test: Are files identical?
    if [ -f "$target" ]; then
        if cmp -s "$source" "$target"; then
            dsc_unchanged "file:$desc"
            return 0
        fi
    fi

    # Set: Copy file
    if cp "$source" "$target"; then
        dsc_changed "file:$desc (updated)"
        return 0
    fi

    dsc_failed "file:$desc"
    return 1
}

# ============================================================================
# Resource: File Template
# ============================================================================

# ensure_file_template <source> <target> <substitutions...>
# Processes template and writes if content differs
# Substitutions format: "{{VAR}}=value"
ensure_file_template() {
    local source=$1
    local target=$2
    shift 2
    local desc=$(basename "$target")

    # Test: Does source exist?
    if [ ! -f "$source" ]; then
        dsc_skipped "template:$desc (source missing)"
        return 1
    fi

    # Build sed expression from substitutions
    local sed_expr=""
    for sub in "$@"; do
        local pattern="${sub%%=*}"
        local value="${sub#*=}"
        sed_expr="$sed_expr -e 's|$pattern|$value|g'"
    done

    # Generate content
    local new_content
    new_content=$(eval "sed $sed_expr" < "$source")

    # Test: Is content identical?
    if [ -f "$target" ]; then
        local current_content
        current_content=$(cat "$target")
        if [ "$new_content" = "$current_content" ]; then
            dsc_unchanged "template:$desc"
            return 0
        fi
    fi

    # Set: Write file
    if echo "$new_content" > "$target"; then
        dsc_changed "template:$desc (updated)"
        return 0
    fi

    dsc_failed "template:$desc"
    return 1
}

# ============================================================================
# Resource: Shell Profile Entry
# ============================================================================

# ensure_profile_entry <marker> <content> [profile_path]
# Ensures a line exists in shell profile (identified by marker)
ensure_profile_entry() {
    local marker=$1
    local content=$2
    local profile=${3:-}

    # Auto-detect profile if not specified
    if [ -z "$profile" ]; then
        if [ "$DSC_PLATFORM" = "mac" ]; then
            profile="$HOME/.zshrc"
        elif [ -f "$HOME/.zshrc" ]; then
            profile="$HOME/.zshrc"
        else
            profile="$HOME/.bashrc"
        fi
    fi

    # Ensure profile exists
    [ ! -f "$profile" ] && touch "$profile"

    # Test: Does marker already exist?
    if grep -q "$marker" "$profile" 2>/dev/null; then
        dsc_unchanged "profile:$marker"
        return 0
    fi

    # Set: Add entry
    echo "" >> "$profile"
    echo "# $marker" >> "$profile"
    echo "$content" >> "$profile"
    dsc_changed "profile:$marker (added to $profile)"
    return 0
}

# ============================================================================
# Resource: Service (launchd/systemd)
# ============================================================================

# ensure_service <name> <plist_or_unit_source>
ensure_service() {
    local name=$1
    local source=$2

    if [ "$DSC_PLATFORM" = "mac" ]; then
        ensure_launchd_service "$name" "$source"
    elif [ "$DSC_PLATFORM" = "linux" ]; then
        ensure_systemd_service "$name" "$source"
    else
        dsc_skipped "service:$name (unsupported platform)"
        return 1
    fi
}

ensure_launchd_service() {
    local name=$1
    local source=$2
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist_path="$plist_dir/$name.plist"

    # Test: Is service already loaded and current?
    if launchctl list | grep -q "$name" 2>/dev/null; then
        if [ -f "$plist_path" ] && [ -f "$source" ]; then
            if cmp -s "$source" "$plist_path"; then
                dsc_unchanged "service:$name (running)"
                return 0
            fi
        fi
    fi

    # Set: Install and load service
    ensure_directory "$plist_dir"

    if [ -f "$source" ]; then
        cp "$source" "$plist_path"
        launchctl unload "$plist_path" 2>/dev/null || true
        if launchctl load "$plist_path" 2>/dev/null; then
            dsc_changed "service:$name (installed and started)"
            return 0
        fi
    fi

    dsc_failed "service:$name"
    return 1
}

# ensure_user_linger
# Enables loginctl linger for current user (required for user services to run after logout)
ensure_user_linger() {
    if [ "$DSC_PLATFORM" != "linux" ]; then
        return 0
    fi

    local uid=$(id -u)

    # Check if linger is already enabled
    if [ -f "/var/lib/systemd/linger/$USER" ] || \
       loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
        dsc_unchanged "systemd:linger (enabled for $USER)"
        return 0
    fi

    # Try to enable linger
    if loginctl enable-linger "$USER" 2>/dev/null; then
        dsc_changed "systemd:linger (enabled for $USER)"
        return 0
    elif sudo loginctl enable-linger "$USER" 2>/dev/null; then
        dsc_changed "systemd:linger (enabled for $USER via sudo)"
        return 0
    fi

    dsc_info "systemd:linger - enable manually: loginctl enable-linger $USER"
    return 1
}

ensure_systemd_service() {
    local name=$1
    local source=$2
    local unit_dir="$HOME/.config/systemd/user"
    local unit_path="$unit_dir/$name"

    # Determine if this is a timer or service
    local unit_type="service"
    [[ "$name" == *.timer ]] && unit_type="timer"

    # Test: Is service/timer enabled and current?
    if systemctl --user is-enabled "$name" &>/dev/null; then
        if [ -f "$unit_path" ] && [ -f "$source" ]; then
            if cmp -s "$source" "$unit_path"; then
                dsc_unchanged "service:$name (enabled)"
                return 0
            fi
        fi
    fi

    # Set: Install and enable
    ensure_directory "$unit_dir"

    if [ -f "$source" ]; then
        cp "$source" "$unit_path"
        systemctl --user daemon-reload 2>/dev/null || true
        if systemctl --user enable --now "$name" 2>/dev/null; then
            dsc_changed "service:$name (installed and enabled)"
            return 0
        fi
    fi

    dsc_failed "service:$name"
    return 1
}

# ============================================================================
# Summary
# ============================================================================

dsc_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${_GREEN}Changed:${_NC}   $DSC_CHANGES"
    echo -e "  ${_BLUE}Unchanged:${_NC} $DSC_UNCHANGED"
    if [ $DSC_FAILED -gt 0 ]; then
        echo -e "  ${_RED}Failed:${_NC}    $DSC_FAILED"
        echo ""
        echo "  Failed resources:"
        for f in "${DSC_FAILURES[@]}"; do
            echo -e "    ${_RED}-${_NC} $f"
        done
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
