#!/bin/bash
#
# Usage Stats Collector for Claude Statusline
# Polls tkn-usage API every 60s, writes cache for statusline to read
#
# Output: ~/.claude/.usage-cache.json
#
# Data sources (all from tkn-usage REST API):
#   - Anthropic API: cost + token usage (today)
#   - Claude subscription: session/weekly quota percentages
#   - GitHub Copilot: premium request %, plan type (via scraper)
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

# Fetch all endpoints in parallel (backgrounded curl)
SUMMARY_FILE=$(mktemp)
QUOTA_FILE=$(mktemp)
COPILOT_SCRAPE_FILE=$(mktemp)
COST_7D_FILE=$(mktemp)
trap 'rm -f "$SUMMARY_FILE" "$QUOTA_FILE" "$COPILOT_SCRAPE_FILE" "$COST_7D_FILE"' EXIT

curl -s --connect-timeout 3 --max-time 5 \
    "$API_BASE/api/v1/summary?starting_at=$TODAY&ending_at=$NOW" \
    > "$SUMMARY_FILE" 2>/dev/null &

curl -s --connect-timeout 3 --max-time 25 \
    "$API_BASE/api/v1/scraper/claude-quota" \
    > "$QUOTA_FILE" 2>/dev/null &

curl -s --connect-timeout 3 --max-time 25 \
    "$API_BASE/api/v1/scraper/github-copilot" \
    > "$COPILOT_SCRAPE_FILE" 2>/dev/null &

curl -s --connect-timeout 3 --max-time 10 \
    "$API_BASE/api/v1/cost/7d" \
    > "$COST_7D_FILE" 2>/dev/null &

wait

# --- Anthropic API usage (cost + tokens) ---
COST="0"
INPUT_TOK="0"
OUTPUT_TOK="0"
ERRORS="{}"

SUMMARY=$(cat "$SUMMARY_FILE")
if [ -n "$SUMMARY" ] && echo "$SUMMARY" | jq -e '.data' &>/dev/null; then
    PARSED=$(echo "$SUMMARY" | jq -c '{
      cost: ([.data.anthropic_cost.data[]?.cost_usd] | add // 0),
      input_tokens: ([.data.anthropic_usage.data[]?.input_tokens] | add // 0),
      output_tokens: ([.data.anthropic_usage.data[]?.output_tokens] | add // 0),
      errors: (.errors // {})
    }' 2>/dev/null)

    if [ -n "$PARSED" ]; then
        COST=$(echo "$PARSED" | jq -r '.cost')
        INPUT_TOK=$(echo "$PARSED" | jq -r '.input_tokens')
        OUTPUT_TOK=$(echo "$PARSED" | jq -r '.output_tokens')
        ERRORS=$(echo "$PARSED" | jq -c '.errors')
    fi
fi

# Validate numeric
[[ "$COST" =~ ^[0-9.]+$ ]] || COST="0"
[[ "$INPUT_TOK" =~ ^[0-9]+$ ]] || INPUT_TOK="0"
[[ "$OUTPUT_TOK" =~ ^[0-9]+$ ]] || OUTPUT_TOK="0"

# --- Claude subscription quota (session/weekly %) ---
CLAUDE_SESSION_PCT="null"
CLAUDE_WEEKLY_PCT="null"
CLAUDE_SONNET_PCT="null"
CLAUDE_SESSION_RESET_AT="null"
CLAUDE_WEEKLY_RESET_AT="null"

QUOTA=$(cat "$QUOTA_FILE")
if [ -n "$QUOTA" ] && echo "$QUOTA" | jq -e '.status == "success"' &>/dev/null; then
    CLAUDE_SESSION_PCT=$(echo "$QUOTA" | jq '.current_session.percent_used // null')
    CLAUDE_WEEKLY_PCT=$(echo "$QUOTA" | jq '.weekly_all_models.percent_used // null')
    CLAUDE_SONNET_PCT=$(echo "$QUOTA" | jq '.weekly_sonnet_only.percent_used // null')
    # Store raw ISO timestamps for compact formatting by statusline
    CLAUDE_SESSION_RESET_AT=$(echo "$QUOTA" | jq '.current_session.resets_at // null')
    CLAUDE_WEEKLY_RESET_AT=$(echo "$QUOTA" | jq '.weekly_all_models.resets_at // null')
fi

# --- GitHub Copilot (premium requests % from scraper) ---
COPILOT_PREMIUM_PCT="null"
COPILOT_PLAN="null"

COPILOT_SCRAPE=$(cat "$COPILOT_SCRAPE_FILE")
if [ -n "$COPILOT_SCRAPE" ] && echo "$COPILOT_SCRAPE" | jq -e '.status == "success"' &>/dev/null; then
    COPILOT_PREMIUM_PCT=$(echo "$COPILOT_SCRAPE" | jq '.premium_requests_percentage // null')
    COPILOT_PLAN=$(echo "$COPILOT_SCRAPE" | jq -r '.plan // null')
fi

# --- 7-day cross-platform cost (Anthropic + LiteLLM/Gemini) ---
COST_7D="null"

COST_7D_RESP=$(cat "$COST_7D_FILE")
if [ -n "$COST_7D_RESP" ] && echo "$COST_7D_RESP" | jq -e '.total_usd' &>/dev/null; then
    COST_7D=$(echo "$COST_7D_RESP" | jq '.total_usd // null')
fi

# Atomic write (tmp + mv prevents partial reads by statusline)
cat > "${CACHE_FILE}.tmp" << EOF
{
  "schema_version": 2,
  "status": "ok",
  "timestamp": $(date +%s),
  "date": "$(date -u +%Y-%m-%d)",
  "cost_usd": $COST,
  "input_tokens": $INPUT_TOK,
  "output_tokens": $OUTPUT_TOK,
  "claude_sub": {
    "session_pct": $CLAUDE_SESSION_PCT,
    "weekly_pct": $CLAUDE_WEEKLY_PCT,
    "sonnet_pct": $CLAUDE_SONNET_PCT,
    "session_reset_at": $CLAUDE_SESSION_RESET_AT,
    "weekly_reset_at": $CLAUDE_WEEKLY_RESET_AT
  },
  "copilot": {
    "premium_pct": $COPILOT_PREMIUM_PCT,
    "plan": "$COPILOT_PLAN"
  },
  "cost_7d_usd": $COST_7D,
  "errors": $ERRORS
}
EOF
mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
