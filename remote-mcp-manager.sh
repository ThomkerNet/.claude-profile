#!/usr/bin/env bash
#
# remote-mcp-manager.sh
# Manages Claude MCP servers on remote host with tmux visibility
# Runs on the REMOTE machine (bnx-macmini-1)
#
# Architecture:
#   - Each 'connect' spawns MCP server in a tmux window (visible on remote)
#   - stdio flows: Claude Desktop <-> SSH <-> tmux pane <-> claude mcp serve
#   - You can attach to tmux on the Mac Mini and watch sessions live
#
# Usage:
#   ./remote-mcp-manager.sh connect <name>  # Called by Claude Desktop via SSH
#   ./remote-mcp-manager.sh list            # List available projects
#   ./remote-mcp-manager.sh watch           # Attach to tmux session to watch
#

set -euo pipefail

TMUX_SESSION="claude-mcp"
GIT_BNX_DIR="$HOME/git-bnx"
LOG_DIR="$HOME/.claude-mcp-logs"

# Project path mapping (name -> path)
declare -A PROJECTS=(
    ["BNX_BNX-Docs-Architecture"]="$GIT_BNX_DIR/BNX/BNX-Docs-Architecture"
    ["BNX_BNX-Docs-Business"]="$GIT_BNX_DIR/BNX/BNX-Docs-Business"
    ["BNX_BNX-TFAzure-SharedServices"]="$GIT_BNX_DIR/BNX/BNX-TFAzure-SharedServices"
    ["BNX_BNX-Web"]="$GIT_BNX_DIR/BNX/BNX-Web"
    ["BNX_BriefHours-App"]="$GIT_BNX_DIR/BNX/BriefHours-App"
    ["BriefHours_BNX-Web"]="$GIT_BNX_DIR/BriefHours/BNX-Web"
    ["BriefHours_BriefHours-App"]="$GIT_BNX_DIR/BriefHours/BriefHours-App"
    ["BriefHours_BriefHours-Deploy"]="$GIT_BNX_DIR/BriefHours/BriefHours-Deploy"
    ["BriefHours_BriefHours-Docs-Architecture"]="$GIT_BNX_DIR/BriefHours/BriefHours-Docs-Architecture"
    ["BriefHours_BriefHours-Docs-Business"]="$GIT_BNX_DIR/BriefHours/BriefHours-Docs-Business"
    ["BriefHours_BriefHours-Inference"]="$GIT_BNX_DIR/BriefHours/BriefHours-Inference"
    ["BriefHours_BriefHours-TFAzure-Infra"]="$GIT_BNX_DIR/BriefHours/BriefHours-TFAzure-Infra"
    ["TKN_TKNet-Claude-General-Chat"]="$GIT_BNX_DIR/TKN/TKNet-Claude-General-Chat"
    ["TKN_TKNet-DockArr-Stack"]="$GIT_BNX_DIR/TKN/TKNet-DockArr-Stack"
)

log_error() { echo "[ERROR] $1" >&2; }

mkdir -p "$LOG_DIR"

# Ensure tmux session exists
ensure_tmux_session() {
    if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        tmux new-session -d -s "$TMUX_SESSION" -n "status"
        tmux send-keys -t "$TMUX_SESSION:status" "echo 'Claude MCP Server Session - $(date)'; echo 'Windows will appear as clients connect'" Enter
    fi
}

# Connect to a project - runs MCP server in tmux window with stdio piped through
connect_server() {
    local name="$1"
    local project_path="${PROJECTS[$name]:-}"

    if [[ -z "$project_path" ]]; then
        log_error "Unknown project: $name"
        log_error "Available: ${!PROJECTS[*]}"
        exit 1
    fi

    if [[ ! -d "$project_path" ]]; then
        log_error "Project directory not found: $project_path"
        exit 1
    fi

    ensure_tmux_session

    # Create unique window name with timestamp to allow multiple connections
    local timestamp
    timestamp=$(date +%H%M%S)
    local window_name="${name}_${timestamp}"

    # Create named pipes for bidirectional communication
    local fifo_in="/tmp/mcp_${name}_${timestamp}_in"
    local fifo_out="/tmp/mcp_${name}_${timestamp}_out"
    mkfifo "$fifo_in" "$fifo_out"

    # Cleanup on exit
    trap "rm -f '$fifo_in' '$fifo_out'" EXIT

    # Create tmux window and start MCP server reading from fifo_in, writing to fifo_out
    tmux new-window -t "$TMUX_SESSION" -n "$window_name"
    tmux send-keys -t "$TMUX_SESSION:$window_name" \
        "cd '$project_path' && echo '[$(date)] MCP server starting for $name' && claude mcp serve < '$fifo_in' | tee -a '$LOG_DIR/${name}.log' > '$fifo_out'; echo '[Session ended]'; sleep 5" Enter

    # Give tmux a moment to start
    sleep 0.2

    # Bridge SSH stdio to the fifos
    # stdin -> fifo_in (to claude), fifo_out -> stdout (from claude)
    # This runs in foreground, connecting Claude Desktop to the tmux-hosted server
    cat > "$fifo_in" &
    cat_pid=$!
    cat < "$fifo_out"

    # Cleanup when client disconnects
    kill $cat_pid 2>/dev/null || true
}

# List available projects
list_projects() {
    echo "Available MCP projects:"
    for name in "${!PROJECTS[@]}"; do
        local path="${PROJECTS[$name]}"
        if [[ -d "$path" ]]; then
            echo "  $name"
        else
            echo "  $name (MISSING: $path)"
        fi
    done | sort
}

# Watch the tmux session
watch_session() {
    ensure_tmux_session
    echo "Attaching to tmux session: $TMUX_SESSION"
    echo "Use Ctrl-b n/p to navigate windows, Ctrl-b d to detach"
    exec tmux attach -t "$TMUX_SESSION"
}

# Show status
show_status() {
    echo "=== Claude MCP Manager Status ==="
    echo ""

    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        echo "Tmux session: RUNNING"
        echo "Windows:"
        tmux list-windows -t "$TMUX_SESSION" -F "  #{window_index}: #{window_name} #{window_active}" 2>/dev/null || true
    else
        echo "Tmux session: NOT RUNNING"
    fi

    echo ""
    echo "Active MCP processes:"
    pgrep -fa "claude mcp serve" 2>/dev/null | head -10 || echo "  (none)"

    echo ""
    echo "To watch live: $0 watch"
    echo "Or: ssh sbarker@bnx-macmini-1 -t 'tmux attach -t $TMUX_SESSION'"
}

# Main
case "${1:-}" in
    connect)
        if [[ -z "${2:-}" ]]; then
            log_error "Usage: $0 connect <project-name>"
            exit 1
        fi
        connect_server "$2"
        ;;
    list)
        list_projects
        ;;
    watch)
        watch_session
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {connect <name>|list|watch|status}"
        echo ""
        list_projects
        exit 1
        ;;
esac
