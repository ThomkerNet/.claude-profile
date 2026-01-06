#!/usr/bin/env bash
# Cross-platform wrapper for telegram-bun scripts
# Usage: run.sh <script-name> [args...]
# Example: run.sh check.ts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$1"
shift

# Find bun executable
if command -v bun &> /dev/null; then
    BUN_CMD="bun"
elif [ -f "$HOME/.bun/bin/bun" ]; then
    BUN_CMD="$HOME/.bun/bin/bun"
elif [ -f "/usr/local/bin/bun" ]; then
    BUN_CMD="/usr/local/bin/bun"
else
    echo "Error: bun not found" >&2
    exit 1
fi

exec "$BUN_CMD" run "$SCRIPT_DIR/$SCRIPT_NAME" "$@"
