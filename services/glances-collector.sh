#!/bin/bash
#
# Glances Stats Collector for Claude Statusline
# Collects CPU/MEM stats every minute, calculates 15-minute averages
#
# Output: ~/.claude/.glances-stats.json
# History: ~/.claude/.glances-history (rolling 15 samples)
#

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CACHE_FILE="$CLAUDE_HOME/.glances-stats.json"
HISTORY_FILE="$CLAUDE_HOME/.glances-history"
MAX_SAMPLES=15  # 15 minutes of 1-minute samples

# Ensure output directory exists
mkdir -p "$CLAUDE_HOME"

# Get current stats from glances
get_current_stats() {
    local cpu_pct mem_pct timestamp

    # Try glances first
    if command -v glances &> /dev/null; then
        # glances --stdout outputs CSV-like data
        # We need to parse the JSON output
        local glances_json
        glances_json=$(glances --stdout cpu.total,mem.percent --stdout-csv 2>/dev/null | tail -1)

        if [ -n "$glances_json" ]; then
            cpu_pct=$(echo "$glances_json" | cut -d',' -f1)
            mem_pct=$(echo "$glances_json" | cut -d',' -f2)
        fi
    fi

    # Fallback to manual collection if glances fails
    if [ -z "$cpu_pct" ] || [ "$cpu_pct" = "None" ]; then
        case "$(uname -s)" in
            Darwin)
                cpu_idle=$(top -l 1 -n 0 2>/dev/null | grep "CPU usage" | awk '{print $7}' | tr -d '%')
                if [ -n "$cpu_idle" ]; then
                    cpu_pct=$(echo "100 - ${cpu_idle%.*}" | bc 2>/dev/null || echo "0")
                else
                    cpu_pct="0"
                fi
                ;;
            Linux)
                cpu_line=$(head -1 /proc/stat 2>/dev/null)
                if [ -n "$cpu_line" ]; then
                    read -ra cpu_vals <<< "$cpu_line"
                    idle=${cpu_vals[4]}
                    total=0
                    for val in "${cpu_vals[@]:1}"; do
                        total=$((total + val))
                    done
                    if [ "$total" -gt 0 ]; then
                        cpu_pct=$(( (total - idle) * 100 / total ))
                    else
                        cpu_pct="0"
                    fi
                else
                    cpu_pct="0"
                fi
                ;;
            *)
                cpu_pct="0"
                ;;
        esac
    fi

    if [ -z "$mem_pct" ] || [ "$mem_pct" = "None" ]; then
        case "$(uname -s)" in
            Darwin)
                pages_free=$(vm_stat 2>/dev/null | awk '/Pages free/ {print $3}' | tr -d '.')
                pages_active=$(vm_stat 2>/dev/null | awk '/Pages active/ {print $3}' | tr -d '.')
                pages_inactive=$(vm_stat 2>/dev/null | awk '/Pages inactive/ {print $3}' | tr -d '.')
                pages_wired=$(vm_stat 2>/dev/null | awk '/Pages wired/ {print $4}' | tr -d '.')
                pages_compressed=$(vm_stat 2>/dev/null | awk '/Pages occupied by compressor/ {print $5}' | tr -d '.')

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
                    mem_pct="0"
                fi
                ;;
            Linux)
                mem_total=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
                mem_available=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
                if [ -n "$mem_total" ] && [ -n "$mem_available" ] && [ "$mem_total" -gt 0 ]; then
                    mem_used=$((mem_total - mem_available))
                    mem_pct=$((mem_used * 100 / mem_total))
                else
                    mem_pct="0"
                fi
                ;;
            *)
                mem_pct="0"
                ;;
        esac
    fi

    timestamp=$(date +%s)
    echo "$timestamp,$cpu_pct,$mem_pct"
}

# Add sample to history and trim old entries
update_history() {
    local sample=$1

    # Append new sample
    echo "$sample" >> "$HISTORY_FILE"

    # Keep only last MAX_SAMPLES lines
    if [ -f "$HISTORY_FILE" ]; then
        tail -n "$MAX_SAMPLES" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"
        mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    fi
}

# Calculate averages from history
calculate_averages() {
    if [ ! -f "$HISTORY_FILE" ]; then
        echo "0:0:0:0"
        return
    fi

    local count=0
    local cpu_sum=0
    local mem_sum=0
    local cpu_current=0
    local mem_current=0

    while IFS=',' read -r ts cpu mem; do
        # Skip empty or malformed lines
        [[ -z "$cpu" || -z "$mem" ]] && continue
        # Remove any decimal points for integer math
        cpu=${cpu%.*}
        mem=${mem%.*}
        cpu_sum=$((cpu_sum + cpu))
        mem_sum=$((mem_sum + mem))
        cpu_current=$cpu
        mem_current=$mem
        count=$((count + 1))
    done < "$HISTORY_FILE"

    if [ "$count" -gt 0 ]; then
        local cpu_avg=$((cpu_sum / count))
        local mem_avg=$((mem_sum / count))
        echo "$cpu_avg:$mem_avg:$cpu_current:$mem_current"
    else
        echo "0:0:0:0"
    fi
}

# Main execution
main() {
    # Get current stats
    local sample
    sample=$(get_current_stats)

    # Update history
    update_history "$sample"

    # Calculate averages
    local avgs
    avgs=$(calculate_averages)
    local cpu_avg=$(echo "$avgs" | cut -d: -f1)
    local mem_avg=$(echo "$avgs" | cut -d: -f2)
    local cpu_current=$(echo "$avgs" | cut -d: -f3)
    local mem_current=$(echo "$avgs" | cut -d: -f4)

    # Count samples for display
    local sample_count
    sample_count=$(wc -l < "$HISTORY_FILE" 2>/dev/null | tr -d ' ')
    sample_count=${sample_count:-0}

    # Write JSON cache
    cat > "$CACHE_FILE" << EOF
{
  "status": "ok",
  "timestamp": $(date +%s),
  "samples": $sample_count,
  "cpu": {
    "current": $cpu_current,
    "avg_15m": $cpu_avg
  },
  "mem": {
    "current": $mem_current,
    "avg_15m": $mem_avg
  }
}
EOF
}

main "$@"
