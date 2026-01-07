#!/usr/bin/env bash
#
# launch-claude-mcp-servers.sh
# Launches Claude Code as MCP servers for all Claude-enabled projects under ~/git-bnx
# Each project runs in its own tmux window
#

set -euo pipefail

TMUX_SESSION="claude-mcp"
GIT_BNX_DIR="$HOME/git-bnx"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Cleanup on failure
cleanup_on_error() {
    log_error "Script failed. To clean up orphaned session: tmux kill-session -t $TMUX_SESSION"
}
trap cleanup_on_error ERR

# Check dependencies
check_dependencies() {
    if ! command -v tmux &> /dev/null; then
        log_error "tmux is not installed"
        exit 1
    fi
    if ! command -v claude &> /dev/null; then
        log_error "claude CLI is not installed"
        exit 1
    fi
}

# Find all Claude-enabled projects (those with CLAUDE.md)
find_claude_projects() {
    find "$GIT_BNX_DIR" -maxdepth 3 -name "CLAUDE.md" -type f 2>/dev/null | \
        xargs -I{} dirname {} | \
        grep -vE '/\.claude(-profile)?$' | \
        sort -u
}

# Get project name with org prefix to prevent collisions
# e.g., ~/git-bnx/BNX/BriefHours-App -> BNX_BriefHours-App
get_project_name() {
    local project_path="$1"
    local project_dir
    local org_dir

    project_dir=$(basename "$project_path")
    org_dir=$(basename "$(dirname "$project_path")")

    echo "${org_dir}_${project_dir}"
}

# Sanitize name for tmux window (replace special chars)
sanitize_window_name() {
    echo "$1" | tr -c '[:alnum:]-' '_' | sed 's/_$//'
}

# Create or attach to tmux session
setup_tmux_session() {
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        log_warn "Session '$TMUX_SESSION' already exists"
        read -p "Kill existing session and restart? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            tmux kill-session -t "$TMUX_SESSION"
            log_info "Killed existing session"
        else
            log_info "Attaching to existing session..."
            tmux attach -t "$TMUX_SESSION"
            exit 0
        fi
    fi

    # Create new session (detached) with status window
    tmux new-session -d -s "$TMUX_SESSION" -n "status"
    tmux send-keys -t "$TMUX_SESSION:status" "echo 'Claude MCP Servers - $(date)'; echo 'Use Ctrl-b n/p to navigate windows'" Enter
    log_info "Created tmux session: $TMUX_SESSION"
}

# Launch Claude MCP server in a new tmux window
launch_mcp_server() {
    local project_path="$1"
    local project_name
    local window_name
    local window_index

    project_name=$(get_project_name "$project_path")
    window_name=$(sanitize_window_name "$project_name")

    # Create new window
    tmux new-window -t "$TMUX_SESSION" -n "$window_name"

    # Get actual window index for reliable send-keys
    window_index=$(tmux list-windows -t "$TMUX_SESSION" -F "#{window_index}:#{window_name}" | grep ":${window_name}$" | cut -d: -f1)

    # Send command to window by index
    tmux send-keys -t "$TMUX_SESSION:${window_index}" "cd \"$project_path\" && claude mcp serve" Enter

    log_info "Launched: $window_name"
}

# Main
main() {
    check_dependencies

    log_info "Scanning for Claude-enabled projects in $GIT_BNX_DIR..."

    local projects=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && projects+=("$line")
    done < <(find_claude_projects)

    if [[ ${#projects[@]} -eq 0 ]]; then
        log_error "No Claude-enabled projects found"
        exit 1
    fi

    log_info "Found ${#projects[@]} Claude-enabled projects"

    # List projects
    echo ""
    echo "Projects to launch:"
    for project in "${projects[@]}"; do
        echo "  - $(get_project_name "$project")"
    done
    echo ""

    read -p "Launch all MCP servers? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted"
        exit 0
    fi

    setup_tmux_session

    # Launch each project
    local launched=0
    for project in "${projects[@]}"; do
        launch_mcp_server "$project"
        ((launched++))
        # Small delay for tmux stability
        sleep 0.3
    done

    # Switch to status window
    tmux select-window -t "$TMUX_SESSION:status"
    tmux send-keys -t "$TMUX_SESSION:status" "echo 'Launched $launched MCP servers'" Enter

    log_info "All $launched MCP servers launched!"
    log_info "Attach with: tmux attach -t $TMUX_SESSION"
    log_info "List windows: tmux list-windows -t $TMUX_SESSION"

    # Optionally attach
    read -p "Attach to session now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        tmux attach -t "$TMUX_SESSION"
    fi
}

main "$@"
