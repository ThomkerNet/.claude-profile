#!/bin/bash
# Background collector for Claude Code status line (SSH sessions)
# Reads saved stdin and computes full status on an interval

INTERVAL="${CLAUDE_STATUSLINE_INTERVAL:-3}"
INPUT_FILE="${HOME}/.claude/.statusline-input"
OUTPUT_FILE="${HOME}/.claude/.statusline-output"
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")

format_tokens() {
    local num=$1
    if [ "$num" -ge 1000 ]; then
        echo $((num / 1000))k
    else
        echo "$num"
    fi
}

compute_status() {
    [ -f "$INPUT_FILE" ] || return

    local data
    data=$(cat "$INPUT_FILE" 2>/dev/null)
    [ -z "$data" ] && return

    # Extract from Claude Code JSON
    local model=$(echo "$data" | jq -r '.model.display_name // "Claude"' 2>/dev/null)
    local fullPath=$(echo "$data" | jq -r '.workspace.current_dir // "."' 2>/dev/null)
    local currentDir=$(echo "$fullPath" | awk -F'/' '{n=NF; if(n>=3) print $(n-2)"/"$(n-1)"/"$n; else if(n==2) print $(n-1)"/"$n; else print $n}')

    local inputTokens=$(echo "$data" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
    local outputTokens=$(echo "$data" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)
    local contextSize=$(echo "$data" | jq -r '.context_window.context_window_size // 200000' 2>/dev/null)
    local costUsd=$(echo "$data" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null)
    local linesAdded=$(echo "$data" | jq -r '.cost.total_lines_added // 0' 2>/dev/null)
    local linesRemoved=$(echo "$data" | jq -r '.cost.total_lines_removed // 0' 2>/dev/null)

    # Ensure numeric
    inputTokens=${inputTokens:-0}; [[ "$inputTokens" =~ ^[0-9]+$ ]] || inputTokens=0
    outputTokens=${outputTokens:-0}; [[ "$outputTokens" =~ ^[0-9]+$ ]] || outputTokens=0
    contextSize=${contextSize:-200000}; [[ "$contextSize" =~ ^[0-9]+$ ]] || contextSize=200000

    local totalTokens=$((inputTokens + outputTokens))
    local contextPct=0
    [ "$contextSize" -gt 0 ] && contextPct=$((totalTokens * 100 / contextSize))

    # Git branch
    local gitBranch=""
    if [ -d "$fullPath" ]; then
        local branch=$(cd "$fullPath" 2>/dev/null && git branch --show-current 2>/dev/null)
        [ -n "$branch" ] && gitBranch=" [$branch]"
    fi

    # Cost string
    local costStr=""
    if command -v bc &>/dev/null && [ "$(echo "$costUsd > 0" | bc -l 2>/dev/null)" = "1" ]; then
        costStr=" • \$$(printf '%.4f' "$costUsd")"
    fi

    # Format output
    printf "%-8s %s:%s%s | %s (%s%%) | +%s -%s%s\n" \
        "[$model]" \
        "$HOSTNAME_SHORT" \
        "$currentDir" \
        "$gitBranch" \
        "$(format_tokens $totalTokens)" \
        "$contextPct" \
        "$linesAdded" \
        "$linesRemoved" \
        "$costStr"
}

# Main loop
while true; do
    result=$(compute_status)
    if [ -n "$result" ]; then
        echo "$result" > "$OUTPUT_FILE"
    fi
    sleep "$INTERVAL"
done
