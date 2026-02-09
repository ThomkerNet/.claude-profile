#!/bin/bash
#
# Usage Stats Collector for Claude Statusline
# Polls tkn-usage API every 60s, writes cache for statusline to read
#
# Output: ~/.claude/.usage-cache.json
#

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CACHE_FILE="$CLAUDE_HOME/.usage-cache.json"
API_BASE="${CLAUDE_USAGE_API_BASE:-https://mcp-usage.gate-hexatonic.ts.net}"

# Require jq
command -v jq &>/dev/null || exit 0

mkdir -p "$CLAUDE_HOME"

# Build today's date range (UTC — matches API server timezone)
TODAY=$(date -u +%Y-%m-%dT00:00:00Z)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Fetch summary (no separate health check — this call handles both)
SUMMARY=$(curl -s --connect-timeout 3 --max-time 5 \
    "$API_BASE/api/v1/summary?starting_at=$TODAY&ending_at=$NOW" 2>/dev/null)

if [ -z "$SUMMARY" ] || ! echo "$SUMMARY" | jq -e '.data' &>/dev/null; then
    exit 0  # Preserve existing cache
fi

# Extract all values in single jq call (reduces coupling to API schema)
PARSED=$(echo "$SUMMARY" | jq -c '{
  cost: ([.data.anthropic_cost.data[]?.cost_usd] | add // 0),
  input_tokens: ([.data.anthropic_usage.data[]?.input_tokens] | add // 0),
  output_tokens: ([.data.anthropic_usage.data[]?.output_tokens] | add // 0),
  copilot_seats: (.data.copilot_billing.seat_breakdown.active_this_cycle // .data.copilot_billing.seat_breakdown.active // 0),
  errors: (.errors // {})
}' 2>/dev/null)

[ -z "$PARSED" ] && exit 0

COST=$(echo "$PARSED" | jq -r '.cost')
INPUT_TOK=$(echo "$PARSED" | jq -r '.input_tokens')
OUTPUT_TOK=$(echo "$PARSED" | jq -r '.output_tokens')
SEATS=$(echo "$PARSED" | jq -r '.copilot_seats')
ERRORS=$(echo "$PARSED" | jq -c '.errors')

# Validate numeric (protect against jq returning null/empty)
[[ "$COST" =~ ^[0-9.]+$ ]] || COST="0"
[[ "$INPUT_TOK" =~ ^[0-9]+$ ]] || INPUT_TOK="0"
[[ "$OUTPUT_TOK" =~ ^[0-9]+$ ]] || OUTPUT_TOK="0"

# Atomic write (tmp + mv prevents partial reads by statusline)
cat > "${CACHE_FILE}.tmp" << EOF
{
  "schema_version": 1,
  "status": "ok",
  "timestamp": $(date +%s),
  "date": "$(date -u +%Y-%m-%d)",
  "cost_usd": $COST,
  "input_tokens": $INPUT_TOK,
  "output_tokens": $OUTPUT_TOK,
  "copilot_seats": $SEATS,
  "errors": $ERRORS
}
EOF
mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
