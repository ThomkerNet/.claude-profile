#!/bin/bash
# Claude Code Status Line - Two-line layout with usage bars
# Line 1: Session info (model, host, path, branch, context, system)
# Line 2: Usage dashboard (Claude sub quota, Copilot premium, API cost)

# ── Helpers ──────────────────────────────────────────────────────────────────

# Mini bar chart: 8 chars wide using Unicode block elements
# Usage: mini_bar <percent> → "▓▓▓▓░░░░ 40%"
mini_bar() {
    local pct=${1:-0}
    local width=8
    # Clamp 0–100
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="▓"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    printf "%s %2d%%" "$bar" "$pct"
}

# Parse ISO 8601 timestamp to epoch seconds (portable: GNU date, BSD date, Python fallback)
iso_to_epoch() {
    local ts="$1"
    local clean_ts
    # Strip fractional seconds, normalize timezone for parsing
    clean_ts=$(echo "$ts" | sed 's/\.[0-9]*//; s/+00:00$/Z/')
    # GNU date (Linux)
    date -d "$clean_ts" +%s 2>/dev/null && return
    # BSD date (macOS) - convert Z suffix to +0000
    local bsd_ts="${clean_ts/Z/+0000}"
    date -j -f "%Y-%m-%dT%H:%M:%S%z" "$bsd_ts" +%s 2>/dev/null && return
    # Python fallback
    python3 -c "from datetime import datetime,timezone; print(int(datetime.fromisoformat('${ts}'.replace('Z','+00:00')).timestamp()))" 2>/dev/null
}

# Compact time-until-reset from ISO timestamp → "r-2h17m" or "r-6d7h"
compact_reset() {
    local ts="$1"
    [ -z "$ts" ] || [ "$ts" = "null" ] && return

    local reset_epoch
    reset_epoch=$(iso_to_epoch "$ts")
    [ -z "$reset_epoch" ] && return

    local now_epoch=$(date +%s)
    local delta=$(( reset_epoch - now_epoch ))
    [ "$delta" -le 0 ] && { echo "r-now"; return; }

    local days=$(( delta / 86400 ))
    local hours=$(( (delta % 86400) / 3600 ))
    local mins=$(( (delta % 3600) / 60 ))

    if [ "$days" -gt 0 ]; then
        printf "r-%dd%dh" "$days" "$hours"
    elif [ "$hours" -gt 0 ]; then
        printf "r-%dh%dm" "$hours" "$mins"
    else
        printf "r-%dm" "$mins"
    fi
}

# Portable "first of next month" as ISO timestamp
next_month_iso() {
    # GNU date
    date -d "$(date +%Y-%m-01) +1 month" +%Y-%m-01T00:00:00Z 2>/dev/null && return
    # BSD date (macOS)
    date -j -v+1m -f "%Y-%m-%d" "$(date +%Y-%m-01)" +%Y-%m-01T00:00:00Z 2>/dev/null && return
    # Python fallback
    python3 -c "from datetime import date; d=date.today().replace(day=1); m=d.month%12+1; y=d.year+(1 if m==1 else 0); print(f'{y}-{m:02d}-01T00:00:00Z')" 2>/dev/null
}

# Format token count as Xk or X.XM
format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        awk -v t="$num" 'BEGIN {printf "%.1fM", t/1000000}'
    elif [ "$num" -ge 1000 ]; then
        echo "$((num / 1000))k"
    else
        echo "$num"
    fi
}

# ── Platform detection ───────────────────────────────────────────────────────

HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")
OS_TYPE="$(uname -s)"

# ── System stats (CPU/MEM from glances cache or instant) ────────────────────

GLANCES_CACHE="${HOME}/.claude/.glances-stats.json"

get_system_stats() {
    local cpu_pct mem_pct

    if [ -f "$GLANCES_CACHE" ]; then
        local cache_time cache_age
        cache_time=$(jq -r '.timestamp // 0' "$GLANCES_CACHE" 2>/dev/null)
        cache_age=$(( $(date +%s) - cache_time ))
        if [ "$cache_age" -lt 120 ]; then
            cpu_pct=$(jq -r '.cpu.avg_15m // .cpu.current // 0' "$GLANCES_CACHE" 2>/dev/null)
            mem_pct=$(jq -r '.mem.avg_15m // .mem.current // 0' "$GLANCES_CACHE" 2>/dev/null)
            if [ -n "$cpu_pct" ] && [ "$cpu_pct" != "null" ] && [ -n "$mem_pct" ] && [ "$mem_pct" != "null" ]; then
                echo "${cpu_pct}:${mem_pct}"; return
            fi
        fi
    fi

    case "$OS_TYPE" in
        Darwin)
            cpu_idle=$(top -l 1 -n 0 2>/dev/null | grep "CPU usage" | awk '{print $7}' | tr -d '%')
            cpu_pct=$([ -n "$cpu_idle" ] && echo $((100 - ${cpu_idle%.*})) || echo "--")
            pages_free=$(vm_stat 2>/dev/null | awk '/Pages free/ {print $3}' | tr -d '.')
            pages_active=$(vm_stat 2>/dev/null | awk '/Pages active/ {print $3}' | tr -d '.')
            pages_wired=$(vm_stat 2>/dev/null | awk '/Pages wired/ {print $4}' | tr -d '.')
            pages_compressed=$(vm_stat 2>/dev/null | awk '/Pages occupied by compressor/ {print $5}' | tr -d '.')
            pages_inactive=$(vm_stat 2>/dev/null | awk '/Pages inactive/ {print $3}' | tr -d '.')
            if [ -n "$pages_free" ] && [ -n "$pages_active" ]; then
                total_pages=$(( ${pages_free:-0} + ${pages_active:-0} + ${pages_inactive:-0} + ${pages_wired:-0} + ${pages_compressed:-0} ))
                used_pages=$(( ${pages_active:-0} + ${pages_wired:-0} + ${pages_compressed:-0} ))
                mem_pct=$([ "$total_pages" -gt 0 ] && echo $((used_pages * 100 / total_pages)) || echo "--")
            else mem_pct="--"; fi
            ;;
        Linux)
            cpu_line=$(head -1 /proc/stat 2>/dev/null)
            if [ -n "$cpu_line" ]; then
                cpu_vals=($cpu_line); idle=${cpu_vals[4]}; total=0
                for val in "${cpu_vals[@]:1}"; do total=$((total + val)); done
                cpu_pct=$([ "$total" -gt 0 ] && echo $(( (total - idle) * 100 / total )) || echo "--")
            else cpu_pct="--"; fi
            mem_total=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
            mem_available=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
            if [ -n "$mem_total" ] && [ -n "$mem_available" ] && [ "$mem_total" -gt 0 ]; then
                mem_pct=$(( (mem_total - mem_available) * 100 / mem_total ))
            else mem_pct="--"; fi
            ;;
        *) cpu_pct="--"; mem_pct="--" ;;
    esac
    echo "${cpu_pct}:${mem_pct}"
}

SYSTEM_STATS=$(get_system_stats)
CPU_PCT=$(echo "$SYSTEM_STATS" | cut -d: -f1)
MEM_PCT=$(echo "$SYSTEM_STATS" | cut -d: -f2)

# ── Read Claude Code JSON from stdin (single jq call) ────────────────────────

command -v jq &>/dev/null || { echo "Error: jq required"; exit 1; }

IFS=$'\t' read -r model fullPath inputTokens outputTokens contextSize costUsd linesAdded linesRemoved < <(
    jq -r '[
        (.model.display_name // "Claude"),
        (.workspace.current_dir // "."),
        (.context_window.total_input_tokens // 0),
        (.context_window.total_output_tokens // 0),
        (.context_window.context_window_size // 200000),
        (.cost.total_cost_usd // 0),
        (.cost.total_lines_added // 0),
        (.cost.total_lines_removed // 0)
    ] | @tsv' 2>/dev/null
)

currentDir=$(echo "$fullPath" | awk -F'/' '{n=NF; if(n>=3) print $(n-2)"/"$(n-1)"/"$n; else if(n==2) print $(n-1)"/"$n; else print $n}')

# Custom session label
customLabel=""
labelFile="${HOME}/.claude/.session-label"
if [ -f "$labelFile" ]; then
    customLabel=$(cat "$labelFile" | tr -d '\n' | tr -d ' ')
    [ -n "$customLabel" ] && customLabel=" • $customLabel"
fi

# Context window (validate numeric)
[[ "$inputTokens" =~ ^[0-9]+$ ]] || inputTokens=0
[[ "$outputTokens" =~ ^[0-9]+$ ]] || outputTokens=0
[[ "$contextSize" =~ ^[0-9]+$ ]] || contextSize=200000
totalTokens=$((inputTokens + outputTokens))
contextPct=0
[ "$contextSize" -gt 0 ] && contextPct=$(( totalTokens * 100 / contextSize ))

# Git branch
gitBranch=""
currentBranch=$(git branch --show-current 2>/dev/null)
[ -n "$currentBranch" ] && gitBranch=" [$currentBranch]"

# Auth mode from settings symlink
authMode=""
settingsLink=$(readlink "$HOME/.claude/settings.json" 2>/dev/null)
case "$settingsLink" in
    *subscription*) authMode="SUB" ;;
    *litellm-claude*) authMode="API" ;;
    *litellm-general*) authMode="LGEN" ;;
    *)
        defaultMode=$(cat "$HOME/.claude/.default-mode" 2>/dev/null)
        case "$defaultMode" in
            subscription) authMode="SUB" ;;
            litellm-claude) authMode="API" ;;
            litellm-general) authMode="LGEN" ;;
        esac ;;
esac

# Spec count
specStr=""
specDir="$fullPath/.claude-specs"
if [ -d "$specDir" ]; then
    specCount=$(find "$specDir" -maxdepth 1 -type f \( -name "*-SPEC.md" -o -name "*-SPEC.MD" \) 2>/dev/null | wc -l | tr -d ' ')
    [ "$specCount" -gt 0 ] && specStr=" SPEC:$specCount"
fi

# ── Read usage cache (tkn-usage MCP server) ──────────────────────────────────

USAGE_CACHE="${CLAUDE_HOME:-$HOME/.claude}/.usage-cache.json"
usage_cost="0"; usage_tokens="0"
sub_session=""; sub_weekly=""; sub_session_reset_at=""; sub_weekly_reset_at=""
cp_premium_pct=""
usage_cache_valid=false
usage_cache_stale=false

if [ -f "$USAGE_CACHE" ] && command -v jq &>/dev/null; then
    read -r cache_time usage_cost usage_tokens \
         sub_session sub_weekly sub_session_reset_at sub_weekly_reset_at \
         cp_premium_pct < <(
        jq -r '[
            (.timestamp // 0),
            (.cost_usd // 0),
            ((.input_tokens // 0) + (.output_tokens // 0)),
            (.claude_sub.session_pct // ""),
            (.claude_sub.weekly_pct // ""),
            (.claude_sub.session_reset_at // ""),
            (.claude_sub.weekly_reset_at // ""),
            (.copilot.premium_pct // "")
        ] | @tsv' "$USAGE_CACHE" 2>/dev/null
    )
    [[ "$cache_time" =~ ^[0-9]+$ ]] || cache_time=0
    cache_age=$(( $(date +%s) - cache_time ))
    if [ "$cache_age" -lt 300 ]; then
        usage_cache_valid=true
    elif [ "$cache_age" -lt 3600 ]; then
        # Stale but usable (API offline) — show data with staleness marker
        usage_cache_valid=true
        usage_cache_stale=true
    fi
fi

# ── Resolve Claude subscription quota (usage-cache > quota-cache > creds) ────

sub_session_bar=""
sub_weekly_bar=""
sub_session_reset=""
sub_weekly_reset=""
quotaLabel=""

if $usage_cache_valid && [ -n "$sub_session" ] && [ "$sub_session" != "null" ]; then
    sub_session_bar=$(mini_bar "$sub_session")
    sub_weekly_bar=$(mini_bar "$sub_weekly")
    sub_session_reset=$(compact_reset "$sub_session_reset_at")
    sub_weekly_reset=$(compact_reset "$sub_weekly_reset_at")
else
    # Fallback: legacy quota-cache
    quotaFile="${HOME}/.claude/.quota-cache"
    if [ -f "$quotaFile" ]; then
        quotaStatus=$(jq -r '.status // "unknown"' "$quotaFile" 2>/dev/null)
        if [ "$quotaStatus" = "ok" ]; then
            sessionPct=$(jq -r '.session.percent // 0' "$quotaFile" 2>/dev/null)
            weeklyPct=$(jq -r '.weekly.percent // 0' "$quotaFile" 2>/dev/null)
            [ "$sessionPct" != "0" ] || [ "$weeklyPct" != "0" ] && {
                sub_session_bar=$(mini_bar "$sessionPct")
                sub_weekly_bar=$(mini_bar "$weeklyPct")
            }
        fi
    fi
    # Fallback: just show plan type
    if [ -z "$sub_session_bar" ]; then
        credsFile="${HOME}/.claude/.credentials.json"
        if [ -f "$credsFile" ]; then
            subType=$(jq -r '.claudeAiOauth.subscriptionType // ""' "$credsFile" 2>/dev/null | tr '[:lower:]' '[:upper:]')
            [ -n "$subType" ] && [ "$subType" != "NULL" ] && quotaLabel="$subType"
        fi
    fi
fi

# ── Copilot premium requests ─────────────────────────────────────────────────

cp_bar=""
cp_reset=""
if $usage_cache_valid && [ -n "$cp_premium_pct" ] && [ "$cp_premium_pct" != "null" ] && [ "$cp_premium_pct" != "" ]; then
    # Round to int for bar chart
    cp_int=$(awk -v p="$cp_premium_pct" 'BEGIN {printf "%d", p + 0.5}')
    cp_bar=$(mini_bar "$cp_int")
    # Copilot resets at start of next month
    next_month=$(next_month_iso)
    [ -n "$next_month" ] && cp_reset=$(compact_reset "$next_month")
fi

# ── API cost/tokens ──────────────────────────────────────────────────────────

apiStr=""
if $usage_cache_valid; then
    if [ "$usage_cost" != "0" ] || [ "$usage_tokens" != "0" ]; then
        tok_fmt=$(format_tokens "$usage_tokens")
        apiStr="API:\$$(LC_NUMERIC=C printf '%.2f' "$usage_cost")/${tok_fmt}"
    fi
fi

# ── Build model display ─────────────────────────────────────────────────────

if [ -n "$authMode" ]; then
    modelDisplay="[$model|$authMode]"
else
    modelDisplay="[$model]"
fi

# ── Session cost string ──────────────────────────────────────────────────────

costStr=""
if awk -v c="$costUsd" 'BEGIN {exit !(c > 0)}' 2>/dev/null; then
    costStr="\$$(LC_NUMERIC=C printf '%.4f' "$costUsd")"
fi

# ── Format context bar ───────────────────────────────────────────────────────

ctxBar=$(mini_bar "$contextPct")

# ── System stats ─────────────────────────────────────────────────────────────

sysStr=""
if [ "$CPU_PCT" != "--" ] && [ "$MEM_PCT" != "--" ]; then
    sysStr="C:${CPU_PCT}% M:${MEM_PCT}%"
elif [ "$CPU_PCT" != "--" ]; then
    sysStr="C:${CPU_PCT}%"
elif [ "$MEM_PCT" != "--" ]; then
    sysStr="M:${MEM_PCT}%"
fi

# ── Terminal width detection ──────────────────────────────────────────────────

TERM_WIDTH=${COLUMNS:-$(tput cols 2>/dev/null)}
TERM_WIDTH=${TERM_WIDTH:-120}

# ── Output ───────────────────────────────────────────────────────────────────
# Line 1: [Model|MODE] host:path [branch] | ctx bar | sys | +N -N $cost
# Line 2: Claude S: bar r-Xh  W: bar r-Xd  |  Copilot: bar r-Xd  |  API: $X/Ytok
#
# Responsive: narrow terminals (<100) drop sys stats and simplify bars

# --- Line 1 ---
line1_parts=()
line1_parts+=("$modelDisplay $HOSTNAME_SHORT:$currentDir$gitBranch$customLabel")
if [ "$TERM_WIDTH" -ge 100 ]; then
    line1_parts+=("ctx $ctxBar $(format_tokens $totalTokens)")
else
    # Compact: just percentage and tokens, no bar
    line1_parts+=("ctx ${contextPct}% $(format_tokens $totalTokens)")
fi
[ -n "$sysStr" ] && [ "$TERM_WIDTH" -ge 120 ] && line1_parts+=("$sysStr")
[ -n "$specStr" ] && line1_parts+=("$specStr")

change_parts=""
[ "$linesAdded" != "0" ] || [ "$linesRemoved" != "0" ] && change_parts="+${linesAdded} -${linesRemoved}"
[ -n "$costStr" ] && change_parts="${change_parts:+$change_parts }$costStr"
[ -n "$change_parts" ] && line1_parts+=("$change_parts")

line1=""
for ((i=0; i<${#line1_parts[@]}; i++)); do
    [ $i -gt 0 ] && line1+=" | "
    line1+="${line1_parts[$i]}"
done

# --- Line 2 ---
line2_parts=()

# Claude subscription
if [ -n "$sub_session_bar" ]; then
    if [ "$TERM_WIDTH" -ge 100 ]; then
        claude_str="Claude S:$sub_session_bar"
        [ -n "$sub_session_reset" ] && claude_str+=" $sub_session_reset"
        claude_str+="  W:$sub_weekly_bar"
        [ -n "$sub_weekly_reset" ] && claude_str+=" $sub_weekly_reset"
    else
        # Narrow: no bars, just percentages
        claude_str="Claude S:${sub_session}%"
        [ -n "$sub_session_reset" ] && claude_str+=" $sub_session_reset"
        claude_str+=" W:${sub_weekly}%"
        [ -n "$sub_weekly_reset" ] && claude_str+=" $sub_weekly_reset"
    fi
    line2_parts+=("$claude_str")
elif [ -n "$quotaLabel" ]; then
    line2_parts+=("Claude $quotaLabel")
fi

# Copilot
if [ -n "$cp_bar" ]; then
    if [ "$TERM_WIDTH" -ge 100 ]; then
        cp_str="Copilot $cp_bar"
    else
        cp_str="CP:${cp_int}%"
    fi
    [ -n "$cp_reset" ] && cp_str+=" $cp_reset"
    line2_parts+=("$cp_str")
fi

# API usage
[ -n "$apiStr" ] && line2_parts+=("$apiStr")

# Add staleness marker if cache is old (API/tailnet offline)
stale_prefix=""
$usage_cache_stale && stale_prefix="~"

line2=""
for ((i=0; i<${#line2_parts[@]}; i++)); do
    [ $i -gt 0 ] && line2+=" | "
    line2+="${line2_parts[$i]}"
done
[ -n "$stale_prefix" ] && [ -n "$line2" ] && line2="${stale_prefix}${line2}"

echo "$line1"
[ -n "$line2" ] && echo "$line2"
