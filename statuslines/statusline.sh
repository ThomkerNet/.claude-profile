#!/bin/bash
# Claude Code Status Line - Cross-platform (Windows/macOS/Linux)
# Reads JSON input from stdin and outputs single-line formatted status
# Note: Only the first line of output is displayed as the status line

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

# Output single-line formatted status
printf "%-8s %s%s%s | %s (%s%%)%s | +%s -%s%s\n" \
    "[$model]" \
    "$currentDir" \
    "$gitBranch" \
    "$customLabel" \
    "$(format_tokens $totalTokens)" \
    "$contextPct" \
    "$quotaStr" \
    "$(echo "$data" | jq -r '.cost.total_lines_added // 0')" \
    "$(echo "$data" | jq -r '.cost.total_lines_removed // 0')" \
    "$costStr"
