#!/bin/bash
#
# Spec Watcher Daemon
# Monitors project directories for new *-SPEC.md files
# Auto-processes specs and logs notifications
#
# Runs via launchd (macOS) or systemd timer (Linux)
#

set -e

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SPEC_REGISTRY="$CLAUDE_HOME/.spec-registry.json"
SPEC_PLANS_DIR="$CLAUDE_HOME/.spec-plans"
LOG_FILE="$CLAUDE_HOME/logs/spec-watcher.log"

# Ensure directories exist
mkdir -p "$SPEC_PLANS_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Initialize registry if it doesn't exist
init_registry() {
    if [ ! -f "$SPEC_REGISTRY" ]; then
        echo '{"specs":[],"projects":[]}' > "$SPEC_REGISTRY"
    fi
}

# Get list of known project directories to watch
# Sources: recent git repos, explicitly registered projects
get_project_dirs() {
    local dirs=()

    # Check registry for explicitly registered projects
    if [ -f "$SPEC_REGISTRY" ] && command -v jq &>/dev/null; then
        while IFS= read -r dir; do
            [ -d "$dir" ] && dirs+=("$dir")
        done < <(jq -r '.projects[]?' "$SPEC_REGISTRY" 2>/dev/null)
    fi

    # Add common git directories
    for base in "$HOME/git" "$HOME/git-bnx" "$HOME/projects" "$HOME/code"; do
        if [ -d "$base" ]; then
            for project in "$base"/*; do
                [ -d "$project/.git" ] && dirs+=("$project")
            done
        fi
    done

    # Deduplicate
    printf '%s\n' "${dirs[@]}" | sort -u
}

# Check if a spec has already been processed
is_spec_processed() {
    local spec_path="$1"
    local spec_hash
    spec_hash=$(md5sum "$spec_path" 2>/dev/null | cut -d' ' -f1 || md5 -q "$spec_path" 2>/dev/null)

    if [ -f "$SPEC_REGISTRY" ] && command -v jq &>/dev/null; then
        jq -e --arg hash "$spec_hash" '.specs[] | select(.hash == $hash)' "$SPEC_REGISTRY" &>/dev/null
        return $?
    fi
    return 1
}

# Register a spec as being processed
register_spec() {
    local spec_path="$1"
    local status="$2"
    local plan_file="$3"
    local spec_hash
    spec_hash=$(md5sum "$spec_path" 2>/dev/null | cut -d' ' -f1 || md5 -q "$spec_path" 2>/dev/null)

    if command -v jq &>/dev/null; then
        local timestamp
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Add to registry
        local new_spec
        new_spec=$(jq -n \
            --arg path "$spec_path" \
            --arg hash "$spec_hash" \
            --arg status "$status" \
            --arg plan "$plan_file" \
            --arg ts "$timestamp" \
            '{path: $path, hash: $hash, status: $status, plan: $plan, timestamp: $ts}')

        jq --argjson spec "$new_spec" '.specs += [$spec]' "$SPEC_REGISTRY" > "${SPEC_REGISTRY}.tmp"
        mv "${SPEC_REGISTRY}.tmp" "$SPEC_REGISTRY"
    fi
}

# Process a new spec file
process_spec() {
    local spec_path="$1"
    local spec_name
    spec_name=$(basename "$spec_path")
    local project_dir
    project_dir=$(dirname "$(dirname "$spec_path")")

    log "Processing new spec: $spec_path"

    # Generate plan filename
    local plan_id
    plan_id=$(date +%s)-$(echo "$spec_path" | md5sum | cut -c1-8 2>/dev/null || echo "$spec_path" | md5 -q | cut -c1-8)
    local plan_file="$SPEC_PLANS_DIR/${plan_id}-PLAN.md"

    # Call the spec processor (TypeScript)
    local processor="$CLAUDE_HOME/services/spec-watcher/processor.ts"
    if [ -f "$processor" ]; then
        local bun_path
        bun_path=$(command -v bun || echo "$HOME/.bun/bin/bun")

        if [ -x "$bun_path" ]; then
            if $bun_path run "$processor" "$spec_path" "$plan_file" >> "$LOG_FILE" 2>&1; then
                register_spec "$spec_path" "planned" "$plan_file"

                # Log notification
                send_notification "$spec_name" "$project_dir" "$plan_file"

                log "Spec processed successfully: $spec_name"
                return 0
            else
                log "Error processing spec: $spec_name"
                register_spec "$spec_path" "error" ""
                return 1
            fi
        fi
    fi

    log "Processor not available, marking spec as pending"
    register_spec "$spec_path" "pending" ""
}

# Log notification about processed spec
send_notification() {
    local spec_name="$1"
    local project_dir="$2"
    local plan_file="$3"

    log "New spec processed: $spec_name in $project_dir"
    log "Plan file: $plan_file"
}

# Main scan loop
scan_for_specs() {
    log "Starting spec scan..."

    local found=0
    while IFS= read -r project_dir; do
        local spec_dir="$project_dir/.claude-specs"

        if [ -d "$spec_dir" ]; then
            for spec_file in "$spec_dir"/*-SPEC.md "$spec_dir"/*-SPEC.MD; do
                [ -f "$spec_file" ] || continue

                if ! is_spec_processed "$spec_file"; then
                    log "Found new spec: $spec_file"
                    process_spec "$spec_file"
                    ((found++))
                fi
            done
        fi
    done < <(get_project_dirs)

    log "Scan complete. Found $found new specs."
}

# Register a project directory
register_project() {
    local project_dir="$1"

    if [ ! -d "$project_dir" ]; then
        echo "Directory does not exist: $project_dir"
        return 1
    fi

    if command -v jq &>/dev/null; then
        # Check if already registered
        if jq -e --arg dir "$project_dir" '.projects | index($dir)' "$SPEC_REGISTRY" &>/dev/null; then
            echo "Project already registered: $project_dir"
            return 0
        fi

        jq --arg dir "$project_dir" '.projects += [$dir]' "$SPEC_REGISTRY" > "${SPEC_REGISTRY}.tmp"
        mv "${SPEC_REGISTRY}.tmp" "$SPEC_REGISTRY"
        echo "Registered project: $project_dir"

        # Create .claude-specs directory
        mkdir -p "$project_dir/.claude-specs"
        echo "Created: $project_dir/.claude-specs"
    fi
}

# List pending specs awaiting user approval
list_pending() {
    if [ -f "$SPEC_REGISTRY" ] && command -v jq &>/dev/null; then
        echo "Pending specs (awaiting approval):"
        echo ""
        jq -r '.specs[] | select(.status == "planned") | "  \(.path)\n    Plan: \(.plan)\n    Created: \(.timestamp)\n"' "$SPEC_REGISTRY"
    fi
}

# Main
init_registry

case "${1:-scan}" in
    scan)
        scan_for_specs
        ;;
    register)
        register_project "$2"
        ;;
    list)
        list_pending
        ;;
    *)
        echo "Usage: $0 {scan|register <dir>|list}"
        exit 1
        ;;
esac
