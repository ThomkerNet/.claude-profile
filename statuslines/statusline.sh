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
    # Truncate to integer (handles floats from cache), then clamp 0–100
    pct=${pct%.*}
    [[ "$pct" =~ ^-?[0-9]+$ ]] || pct=0
    (( pct > 100 )) && pct=100
    (( pct < 0 )) && pct=0
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
    python3 - "$ts" 2>/dev/null <<'PY'
import sys
from datetime import datetime
ts = sys.argv[1].replace('Z', '+00:00')
print(int(datetime.fromisoformat(ts).timestamp()))
PY
}

# Compact time-until-reset from ISO timestamp → "r-2h17m" or "r-6d7h"
compact_reset() {
    local ts="$1"
    [ -z "$ts" ] || [ "$ts" = "null" ] && return

    local reset_epoch
    reset_epoch=$(iso_to_epoch "$ts")
    [ -z "$reset_epoch" ] && return

    local now_epoch=$NOW_EPOCH
    local delta=$(( reset_epoch - now_epoch ))
    [ "$delta" -le 0 ] && { echo "rnow"; return; }

    local days=$(( delta / 86400 ))
    local hours=$(( (delta % 86400) / 3600 ))
    local mins=$(( (delta % 3600) / 60 ))

    if [ "$days" -gt 0 ]; then
        printf "r%dd" "$days"
    elif [ "$hours" -gt 0 ]; then
        printf "r%dh" "$hours"
    else
        printf "r%dm" "$mins"
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

# ── Colors ───────────────────────────────────────────────────────────────────

DIM=$'\e[2m'
CYAN=$'\e[36m'
YELLOW=$'\e[33m'
GREEN=$'\e[32m'
RED=$'\e[31m'
RST=$'\e[0m'

# Bar colored by percentage: green <70, yellow 70–89, red ≥90
colored_bar() {
    local pct=${1:-0}
    pct=${pct%.*}
    [[ "$pct" =~ ^-?[0-9]+$ ]] || pct=0
    local col
    if (( pct >= 90 )); then col="$RED"
    elif (( pct >= 70 )); then col="$YELLOW"
    else col="$GREEN"
    fi
    printf '%s%s%s' "$col" "$(mini_bar "$pct")" "$RST"
}

# ── Platform detection ───────────────────────────────────────────────────────

NOW_EPOCH=$(date +%s)
HOSTNAME_SHORT="${HOSTNAME%%.*}"
[[ -z "$HOSTNAME_SHORT" ]] && HOSTNAME_SHORT=$(hostname 2>/dev/null || echo "unknown")
OS_TYPE="$(uname -s)"

# ── System stats (CPU/MEM from glances cache or instant) ────────────────────

GLANCES_CACHE="${HOME}/.claude/.glances-stats.json"

get_system_stats() {
    local cpu_pct mem_pct

    if [ -f "$GLANCES_CACHE" ]; then
        local cache_time cache_age
        cache_time=$(jq -r '.timestamp // 0' "$GLANCES_CACHE" 2>/dev/null)
        cache_age=$(( NOW_EPOCH - cache_time ))
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
CPU_PCT=${SYSTEM_STATS%%:*}
MEM_PCT=${SYSTEM_STATS#*:}

# ── Read Claude Code JSON from stdin ─────────────────────────────────────────

command -v jq &>/dev/null || { echo "Error: jq required"; exit 1; }

# Capture stdin so we can optionally debug it
_json=$(cat)
# Debug mode: CLAUDE_STATUSLINE_DEBUG=1 captures raw JSON for inspection
[ "${CLAUDE_STATUSLINE_DEBUG:-0}" = "1" ] && echo "$_json" > "${HOME}/.claude/.statusline-debug.json"

IFS=$'\t' read -r model fullPath contextPct currentTokens costUsd linesAdded linesRemoved < <(
    echo "$_json" | jq -r '[
        (.model.display_name // "Claude"),
        (.workspace.current_dir // "."),
        (.context_window.used_percentage // 0),
        ((.context_window.current_usage.input_tokens // 0)
          + (.context_window.current_usage.output_tokens // 0)
          + (.context_window.current_usage.cache_creation_input_tokens // 0)
          + (.context_window.current_usage.cache_read_input_tokens // 0)),
        (.cost.total_cost_usd // 0),
        (.cost.total_lines_added // 0),
        (.cost.total_lines_removed // 0)
    ] | @tsv' 2>/dev/null
)

currentDir=$(echo "$fullPath" | awk -F'/' '{n=NF; if(n>=2) print $(n-1)"/"$n; else print $n}')

# Custom session label: the statusline runs as Claude Code → bash-wrapper → statusline.sh
# so $PPID is the bash-wrapper and its parent is the Claude Code process.
# Use one ps call to get the grandparent (Claude Code PID) — same as what /cname writes.
customLabel=""
_session_pid=$(ps -p "$PPID" -o ppid= 2>/dev/null | tr -d ' ')
[ -z "$_session_pid" ] && _session_pid="$PPID"
labelFile="${HOME}/.claude/.session-label-${_session_pid}"
[ -f "$labelFile" ] || labelFile="${HOME}/.claude/.session-label-${PPID}"
[ -f "$labelFile" ] || labelFile="${HOME}/.claude/.session-label"
if [ -f "$labelFile" ]; then
    customLabel=$(tr -d '\n ' < "$labelFile")
    [ -n "$customLabel" ] && customLabel="${YELLOW}${customLabel}${RST} • "
fi

# Context window (validate numeric)
[[ "$contextPct" =~ ^[0-9]+$ ]] || contextPct=0
[[ "$currentTokens" =~ ^[0-9]+$ ]] || currentTokens=0

# Git branch
gitBranch=""
currentBranch=$(git branch --show-current 2>/dev/null)
[ -n "$currentBranch" ] && gitBranch=" ${CYAN}[${currentBranch}]${RST}"


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
    # Use mapfile (array) instead of read+@tsv to preserve empty fields.
    # bash read collapses consecutive tabs (whitespace IFS) which drops null fields.
    mapfile -t _u < <(
        jq -r '
            (.timestamp // 0),
            (.cost_usd // 0),
            ((.input_tokens // 0) + (.output_tokens // 0)),
            (.claude_sub.session_pct // ""),
            (.claude_sub.weekly_pct // ""),
            (.claude_sub.session_reset_at // ""),
            (.claude_sub.weekly_reset_at // ""),
            (.copilot.premium_pct // ""),
            (.cost_7d_usd // "")
        ' "$USAGE_CACHE" 2>/dev/null
    )
    cache_time="${_u[0]:-0}"
    usage_cost="${_u[1]:-0}"
    usage_tokens="${_u[2]:-0}"
    sub_session="${_u[3]}"
    sub_weekly="${_u[4]}"
    sub_session_reset_at="${_u[5]}"
    sub_weekly_reset_at="${_u[6]}"
    cp_premium_pct="${_u[7]}"
    cost_7d="${_u[8]}"
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
    sub_session_bar=$(colored_bar "$sub_session")
    sub_weekly_bar=$(colored_bar "$sub_weekly")
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
            if [ "$sessionPct" != "0" ] || [ "$weeklyPct" != "0" ]; then
                sub_session_bar=$(mini_bar "$sessionPct")
                sub_weekly_bar=$(mini_bar "$weeklyPct")
            fi
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
    cp_bar=$(colored_bar "$cp_int")
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

# ── 7-day cross-platform cost ─────────────────────────────────────────────────

cost7dStr=""
if $usage_cache_valid && [ -n "$cost_7d" ] && [ "$cost_7d" != "null" ] && [ "$cost_7d" != "0" ]; then
    cost7dStr="${DIM}🦞7d:\$${RST}$(LC_NUMERIC=C printf '%.2f' "$cost_7d")"
fi

# ── Build model display ─────────────────────────────────────────────────────

modelDisplay="${DIM}[${RST}${model}${DIM}]${RST}"

# ── Session cost string ──────────────────────────────────────────────────────

costStr=""
if awk -v c="$costUsd" 'BEGIN {exit !(c > 0)}' 2>/dev/null; then
    costStr="${YELLOW}\$$(LC_NUMERIC=C printf '%.4f' "$costUsd")${RST}"
fi

# ── Format context bar ───────────────────────────────────────────────────────

ctxBar=$(colored_bar "$contextPct")

# ── System stats (only shown when above threshold, in red) ───────────────────

CPU_THRESHOLD=80
MEM_THRESHOLD=85
sysStr=""
cpu_hi=false; mem_hi=false
[[ "$CPU_PCT" =~ ^[0-9]+$ ]] && (( CPU_PCT >= CPU_THRESHOLD )) && cpu_hi=true
[[ "$MEM_PCT" =~ ^[0-9]+$ ]] && (( MEM_PCT >= MEM_THRESHOLD )) && mem_hi=true
if $cpu_hi || $mem_hi; then
    sysStr="${RED}C:${CPU_PCT}% M:${MEM_PCT}%${RST}"
fi

# ── Output ───────────────────────────────────────────────────────────────────
# Line 1: [Model] host:path [branch] | ctx bar | sys | +N -N $cost
# Line 2: Claude S: bar r-Xh  W: bar r-Xd  |  Copilot: bar r-Xd  |  API: $X/Ytok

# --- Line 1 ---
line1_parts=()
line1_parts+=("${customLabel}${modelDisplay} ${DIM}${HOSTNAME_SHORT}:${RST}${currentDir}${gitBranch}")
line1_parts+=("${DIM}ctx${RST} ${ctxBar} ${DIM}$(format_tokens "$currentTokens")${RST}")
[ -n "$sysStr" ] && line1_parts+=("$sysStr")
[ -n "$specStr" ] && line1_parts+=("$specStr")
[ -n "$costStr" ] && line1_parts+=("$costStr")

line1=""
for ((i=0; i<${#line1_parts[@]}; i++)); do
    [ $i -gt 0 ] && line1+=" | "
    line1+="${line1_parts[$i]}"
done

# --- Line 2 ---
line2_parts=()

# Claude subscription
if [ -n "$sub_session_bar" ]; then
    claude_str="${DIM}Claude sess:${RST}${sub_session_bar}"
    [ -n "$sub_session_reset" ] && claude_str+=" ${DIM}${CYAN}${sub_session_reset}${RST}"
    claude_str+="  ${DIM}wk:${RST}${sub_weekly_bar}"
    [ -n "$sub_weekly_reset" ] && claude_str+=" ${DIM}${CYAN}${sub_weekly_reset}${RST}"
    line2_parts+=("$claude_str")
elif [ -n "$quotaLabel" ]; then
    line2_parts+=("${DIM}Claude${RST} $quotaLabel")
fi

# Copilot
if [ -n "$cp_bar" ]; then
    cp_str="${DIM}Copilot${RST} ${cp_bar}"
    [ -n "$cp_reset" ] && cp_str+=" ${DIM}${CYAN}${cp_reset}${RST}"
    line2_parts+=("$cp_str")
fi

# API usage (today)
[ -n "$apiStr" ] && line2_parts+=("$apiStr")

# 7-day cross-platform cost
[ -n "$cost7dStr" ] && line2_parts+=("$cost7dStr")

# Add staleness marker if cache is old (API/tailnet offline)
stale_prefix=""
$usage_cache_stale && stale_prefix="${YELLOW}~${RST}"

line2=""
for ((i=0; i<${#line2_parts[@]}; i++)); do
    [ $i -gt 0 ] && line2+=" | "
    line2+="${line2_parts[$i]}"
done
[ -n "$stale_prefix" ] && [ -n "$line2" ] && line2="${stale_prefix}${line2}"

echo "$line1"
[ -n "$line2" ] && echo "$line2"
