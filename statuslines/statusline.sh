#!/bin/bash
# Claude Code Status Line - Cross-platform (Windows/macOS/Linux)
# Reads JSON input from stdin and outputs single-line formatted status
# Note: Only the first line of output is displayed as the status line

# Get hostname (short form)
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")

# Skip custom status line over SSH to prevent flashing
# Claude Code redraws on every keystroke; even cached output causes flicker
if [ -n "$SSH_CONNECTION" ]; then
    cat > /dev/null  # consume stdin
    exit 1  # error exit - might disable status line entirely
fi

# Detect platform
OS_TYPE="$(uname -s)"

# Read system stats from glances collector cache (15-min averages)
# Falls back to instant readings if cache unavailable
GLANCES_CACHE="${HOME}/.claude/.glances-stats.json"

get_system_stats() {
    local cpu_pct mem_pct

    # Try reading from glances cache first (has 15-min averages)
    if [ -f "$GLANCES_CACHE" ]; then
        local cache_age
        local cache_time
        cache_time=$(jq -r '.timestamp // 0' "$GLANCES_CACHE" 2>/dev/null)
        cache_age=$(( $(date +%s) - cache_time ))

        # Use cache if less than 2 minutes old
        if [ "$cache_age" -lt 120 ]; then
            cpu_pct=$(jq -r '.cpu.avg_15m // .cpu.current // 0' "$GLANCES_CACHE" 2>/dev/null)
            mem_pct=$(jq -r '.mem.avg_15m // .mem.current // 0' "$GLANCES_CACHE" 2>/dev/null)
            if [ -n "$cpu_pct" ] && [ "$cpu_pct" != "null" ] && [ -n "$mem_pct" ] && [ "$mem_pct" != "null" ]; then
                echo "${cpu_pct}:${mem_pct}"
                return
            fi
        fi
    fi

    # Fallback: instant readings
    case "$OS_TYPE" in
        Darwin)
            cpu_idle=$(top -l 1 -n 0 2>/dev/null | grep "CPU usage" | awk '{print $7}' | tr -d '%')
            if [ -n "$cpu_idle" ]; then
                cpu_pct=$((100 - ${cpu_idle%.*}))
            else
                cpu_pct="--"
            fi

            pages_free=$(vm_stat 2>/dev/null | awk '/Pages free/ {print $3}' | tr -d '.')
            pages_active=$(vm_stat 2>/dev/null | awk '/Pages active/ {print $3}' | tr -d '.')
            pages_inactive=$(vm_stat 2>/dev/null | awk '/Pages inactive/ {print $3}' | tr -d '.')
            pages_wired=$(vm_stat 2>/dev/null | awk '/Pages wired/ {print $4}' | tr -d '.')
            pages_compressed=$(vm_stat 2>/dev/null | awk '/Pages occupied by compressor/ {print $5}' | tr -d '.')

            if [ -n "$pages_free" ] && [ -n "$pages_active" ]; then
                pages_free=${pages_free:-0}
                pages_active=${pages_active:-0}
                pages_inactive=${pages_inactive:-0}
                pages_wired=${pages_wired:-0}
                pages_compressed=${pages_compressed:-0}
                total_pages=$((pages_free + pages_active + pages_inactive + pages_wired + pages_compressed))
                used_pages=$((pages_active + pages_wired + pages_compressed))
                if [ "$total_pages" -gt 0 ]; then
                    mem_pct=$((used_pages * 100 / total_pages))
                else
                    mem_pct="--"
                fi
            else
                mem_pct="--"
            fi
            ;;
        Linux)
            cpu_line=$(head -1 /proc/stat 2>/dev/null)
            if [ -n "$cpu_line" ]; then
                cpu_vals=($cpu_line)
                idle=${cpu_vals[4]}
                total=0
                for val in "${cpu_vals[@]:1}"; do
                    total=$((total + val))
                done
                if [ "$total" -gt 0 ]; then
                    cpu_pct=$(( (total - idle) * 100 / total ))
                else
                    cpu_pct="--"
                fi
            else
                cpu_pct="--"
            fi

            mem_total=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
            mem_available=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
            if [ -n "$mem_total" ] && [ -n "$mem_available" ] && [ "$mem_total" -gt 0 ]; then
                mem_used=$((mem_total - mem_available))
                mem_pct=$((mem_used * 100 / mem_total))
            else
                mem_pct="--"
            fi
            ;;
        *)
            cpu_pct="--"
            mem_pct="--"
            ;;
    esac

    echo "${cpu_pct}:${mem_pct}"
}

# Get system stats
SYSTEM_STATS=$(get_system_stats)
CPU_PCT=$(echo "$SYSTEM_STATS" | cut -d: -f1)
MEM_PCT=$(echo "$SYSTEM_STATS" | cut -d: -f2)

# Read JSON from stdin
input=$(cat)
data=$(echo "$input" | jq -r '.' 2>/dev/null)

# Check if jq is available
if [ $? -ne 0 ]; then
    echo "Error: jq required"
    exit 1
fi

# Extract values using jq
model=$(echo "$data" | jq -r '.model.display_name // "Claude"')
# Get last 3 path segments (e.g., git-bnx/project/src)
fullPath=$(echo "$data" | jq -r '.workspace.current_dir // "."')
currentDir=$(echo "$fullPath" | awk -F'/' '{n=NF; if(n>=3) print $(n-2)"/"$(n-1)"/"$n; else if(n==2) print $(n-1)"/"$n; else print $n}')

# Read custom session label if it exists (set via /cname command)
customLabel=""
labelFile="${HOME}/.claude/.session-label"
if [ -f "$labelFile" ]; then
    customLabel=$(cat "$labelFile" | tr -d '\n' | tr -d ' ')
    if [ -n "$customLabel" ]; then
        customLabel=" • $customLabel"
    fi
fi

# Context window metrics (ensure integer defaults)
inputTokens=$(echo "$data" | jq -r '.context_window.total_input_tokens // 0')
outputTokens=$(echo "$data" | jq -r '.context_window.total_output_tokens // 0')
contextSize=$(echo "$data" | jq -r '.context_window.context_window_size // 200000')

# Ensure numeric values (default to 0 if empty/null)
inputTokens=${inputTokens:-0}
outputTokens=${outputTokens:-0}
contextSize=${contextSize:-200000}
[[ "$inputTokens" =~ ^[0-9]+$ ]] || inputTokens=0
[[ "$outputTokens" =~ ^[0-9]+$ ]] || outputTokens=0
[[ "$contextSize" =~ ^[0-9]+$ ]] || contextSize=200000

# Cost metrics
costUsd=$(echo "$data" | jq -r '.cost.total_cost_usd // 0')

# Format tokens as Xk
format_tokens() {
    local num=$1
    if [ "$num" -ge 1000 ]; then
        echo $((num / 1000))k
    else
        echo "$num"
    fi
}

totalTokens=$((inputTokens + outputTokens))

# Get git branch if in a repo
gitBranch=""
currentBranch=$(git branch --show-current 2>/dev/null)
if [ -n "$currentBranch" ]; then
    gitBranch=" [$currentBranch]"
fi

# Calculate context usage percentage
if [ "$contextSize" -gt 0 ]; then
    contextPct=$(echo "scale=0; ($totalTokens * 100) / $contextSize" | bc 2>/dev/null || echo "0")
else
    contextPct="0"
fi

# Format cost (only show if > 0)
costStr=""
if (( $(echo "$costUsd > 0" | bc -l 2>/dev/null) )); then
    costStr=" • \$$(printf '%.4f' "$costUsd")"
fi

# Read Max quota from cache (fetched separately)
quotaStr=""
quotaFile="${HOME}/.claude/.quota-cache"
if [ -f "$quotaFile" ]; then
    quotaStatus=$(jq -r '.status // "unknown"' "$quotaFile" 2>/dev/null)
    if [ "$quotaStatus" = "ok" ]; then
        # New format: session, weekly, sonnet
        sessionPct=$(jq -r '.session.percent // 0' "$quotaFile" 2>/dev/null)
        weeklyPct=$(jq -r '.weekly.percent // 0' "$quotaFile" 2>/dev/null)
        # Show: S:session% W:weekly%
        if [ "$sessionPct" != "0" ] || [ "$weeklyPct" != "0" ]; then
            quotaStr=" | S:${sessionPct}% W:${weeklyPct}%"
        fi
    elif [ "$quotaStatus" = "auth_required" ]; then
        quotaStr=" | Q:login"
    fi
fi

# Format system stats string
sysStatsStr=""
if [ "$CPU_PCT" != "--" ] || [ "$MEM_PCT" != "--" ]; then
    sysStatsStr=" | C:${CPU_PCT}% M:${MEM_PCT}%"
fi

# Check for pending specs in current project
specStr=""
specDir="$fullPath/.claude-specs"
if [ -d "$specDir" ]; then
    specCount=$(find "$specDir" -maxdepth 1 -name "*-SPEC.md" -o -name "*-SPEC.MD" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$specCount" -gt 0 ]; then
        specStr=" | SPEC:$specCount"
    fi
fi

# Output single-line formatted status
# Format: [model] host:path [branch] | tokens (ctx%) quota | sys | specs | +lines -lines cost
output=$(printf "%-8s %s:%s%s%s | %s (%s%%)%s%s%s | +%s -%s%s\n" \
    "[$model]" \
    "$HOSTNAME_SHORT" \
    "$currentDir" \
    "$gitBranch" \
    "$customLabel" \
    "$(format_tokens $totalTokens)" \
    "$contextPct" \
    "$quotaStr" \
    "$sysStatsStr" \
    "$specStr" \
    "$(echo "$data" | jq -r '.cost.total_lines_added // 0')" \
    "$(echo "$data" | jq -r '.cost.total_lines_removed // 0')" \
    "$costStr")

# Cache output for SSH throttling
if [ -n "$SSH_CONNECTION" ]; then
    echo "$output" > "$CACHE_FILE"
fi
echo "$output"
