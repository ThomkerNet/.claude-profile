#!/bin/bash
#
# Usage Stats Collector for Claude Statusline
# Polls tkn-usage /api/v1/status-cache every 60s, writes cache for statusline
#
# Output: ~/.claude/.usage-cache.json
#
# The status-cache endpoint aggregates all data sources server-side in parallel:
#   - Anthropic API costs (1d + 7d)
#   - Gemini API costs (1d + 7d) across both gateways
#   - Claude subscription quota (session/weekly %)
#   - GitHub Copilot premium request %
#   - Anthropic today cost/tokens from usage DB
#

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CACHE_FILE="$CLAUDE_HOME/.usage-cache.json"
API_BASE="${CLAUDE_USAGE_API_BASE:-https://mcp-usage.gate-hexatonic.ts.net}"

mkdir -p "$CLAUDE_HOME"

# Single endpoint returns the complete cache document — atomic write
curl -sf --connect-timeout 5 --max-time 30 \
    "$API_BASE/api/v1/status-cache" \
    > "${CACHE_FILE}.tmp" 2>/dev/null \
    && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
