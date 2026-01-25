#!/usr/bin/env bash
# Obsidian Git Sync - Automatic commit and push
#
# Safety features:
# - Lock file prevents concurrent runs
# - Detects stuck rebase/merge states
# - File stability check (waits for Obsidian Sync to finish writing)
# - Aborts if >500 files changed (likely corruption/mistake)
# - Aborts if diff >10000 lines changed (large binary or mistake)
# - Conflicts require manual resolution (alerts via log + optional Telegram)
# - Log rotation (max 10MB)
#
# Usage:
#   OBSIDIAN_VAULT_PATH=~/Documents/SBarker-Vault ./sync.sh
#
# Environment variables:
#   OBSIDIAN_VAULT_PATH  - Path to Obsidian vault (required)
#   OBSIDIAN_SYNC_LOG    - Log file path (default: ~/.claude/logs/obsidian-sync.log)

set -eo pipefail

VAULT_PATH="${OBSIDIAN_VAULT_PATH:-$HOME/Documents/SBarker-Vault}"
LOG_FILE="${OBSIDIAN_SYNC_LOG:-$HOME/.claude/logs/obsidian-sync.log}"
LOCK_DIR="/tmp/obsidian-sync.lock"
MAX_FILES_CHANGED=500
MAX_LINES_CHANGED=10000
STABILITY_WAIT=3  # seconds to wait for file changes to settle

# ============================================================================
# Logging with rotation
# ============================================================================

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"

    # Rotate if > 10MB
    if [ -f "$LOG_FILE" ]; then
        local size
        size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 10485760 ]; then
            mv "$LOG_FILE" "$LOG_FILE.old"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log rotated" > "$LOG_FILE"
        fi
    fi
}

alert() {
    log "ALERT: $1"
    # Optional: Send Telegram notification if configured
    if [ -f "$HOME/.claude/.telegram-config.json" ] && command -v bun &>/dev/null; then
        bun run "$HOME/.claude/hooks/telegram-bun/index.ts" send "🔴 Obsidian Sync: $1" 2>/dev/null || true
    fi
}

# ============================================================================
# Setup
# ============================================================================

mkdir -p "$(dirname "$LOG_FILE")"

# Acquire lock (atomic mkdir)
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    # Check if stale lock (older than 5 minutes)
    if [ -d "$LOCK_DIR" ]; then
        lock_mtime=$(stat -f%m "$LOCK_DIR" 2>/dev/null || stat -c%Y "$LOCK_DIR" 2>/dev/null || echo 0)
        if [ "$lock_mtime" -eq 0 ]; then
            log "Cannot stat lock directory, exiting"
            exit 0
        fi
        lock_age=$(($(date +%s) - lock_mtime))
        if [ "$lock_age" -gt 300 ]; then
            # Atomic replace: remove + acquire in one check to avoid race
            if rmdir "$LOCK_DIR" 2>/dev/null && mkdir "$LOCK_DIR" 2>/dev/null; then
                log "Acquired stale lock (was ${lock_age}s old)"
            else
                exit 0  # Someone else got it
            fi
        else
            exit 0  # Another instance running, silent exit
        fi
    else
        exit 0
    fi
fi
trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT

# ============================================================================
# Validation
# ============================================================================

if [ ! -d "$VAULT_PATH/.git" ]; then
    log "ERROR: $VAULT_PATH is not a git repository"
    exit 1
fi

cd "$VAULT_PATH"

# Check for stuck rebase/merge state
if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then
    alert "Rebase in progress - manual intervention required: cd $VAULT_PATH && git rebase --abort"
    exit 1
fi

if [ -f ".git/MERGE_HEAD" ]; then
    alert "Merge in progress - manual intervention required: cd $VAULT_PATH && git merge --abort"
    exit 1
fi

# Get current branch dynamically (fail if detached HEAD)
if ! BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null); then
    alert "Detached HEAD state - cannot sync: cd $VAULT_PATH && git checkout main"
    exit 1
fi

# ============================================================================
# File Stability Check (wait for Obsidian Sync to finish writing)
# ============================================================================

get_vault_hash() {
    # Hash of all file modification times (excluding .git)
    find . -type f -not -path './.git/*' -exec stat -f '%m' {} \; 2>/dev/null | md5 || \
    find . -type f -not -path './.git/*' -exec stat -c '%Y' {} \; 2>/dev/null | md5sum | cut -d' ' -f1
}

HASH1=$(get_vault_hash)
if [ -z "$HASH1" ]; then
    log "ERROR: Cannot read vault files for stability check"
    exit 1
fi

sleep "$STABILITY_WAIT"
HASH2=$(get_vault_hash)

if [ -z "$HASH2" ] || [ "$HASH1" != "$HASH2" ]; then
    log "Files still changing (Obsidian Sync active?), deferring"
    exit 0
fi

# ============================================================================
# Fetch and Check Remote
# ============================================================================

if ! git fetch origin "$BRANCH" 2>&1 | while read -r line; do [ -n "$line" ] && log "fetch: $line"; done; then
    log "Fetch failed, continuing with local state"
fi

# Check if remote has changes we don't have
if ! LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null); then
    log "No commits yet in repository, skipping sync"
    exit 0
fi

# Check if remote branch exists
if ! REMOTE_HEAD=$(git rev-parse "origin/$BRANCH" 2>/dev/null); then
    log "Remote branch origin/$BRANCH doesn't exist yet, will push to create it"
    REMOTE_HEAD="$LOCAL_HEAD"
    MERGE_BASE="$LOCAL_HEAD"
else
    if ! MERGE_BASE=$(git merge-base HEAD "origin/$BRANCH" 2>/dev/null); then
        alert "Cannot determine merge base - no common history with remote"
        exit 1
    fi
fi

# ============================================================================
# Handle Different Sync States
# ============================================================================

CHANGED_FILES=$(git status --porcelain | wc -l | tr -d ' ')

# Case 1: No local changes
if [ "$CHANGED_FILES" -eq 0 ]; then
    if [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then
        # Fully in sync, nothing to do
        exit 0
    elif [ "$LOCAL_HEAD" = "$MERGE_BASE" ]; then
        # Remote is ahead, safe to pull (fast-forward)
        log "Pulling remote changes (fast-forward)..."
        if git pull --ff-only origin "$BRANCH" 2>&1 | while read -r line; do [ -n "$line" ] && log "pull: $line"; done; then
            log "SUCCESS: Pulled from remote"
        else
            alert "Pull failed - check $LOG_FILE"
        fi
        exit 0
    elif [ "$REMOTE_HEAD" = "$MERGE_BASE" ]; then
        # We're ahead of remote, nothing to commit but may need to push
        log "Local ahead of remote, checking for unpushed commits..."
        UNPUSHED=$(git log "origin/$BRANCH..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')
        if [ "$UNPUSHED" -gt 0 ]; then
            log "Pushing $UNPUSHED unpushed commit(s)..."
            if git push origin "$BRANCH" 2>&1 | while read -r line; do [ -n "$line" ] && log "push: $line"; done; then
                log "SUCCESS: Pushed $UNPUSHED commit(s)"
            else
                alert "Push failed - check $LOG_FILE"
            fi
        fi
        exit 0
    else
        # Diverged with no local changes - unusual, might be force-pushed remote
        alert "Local and remote have diverged (no local changes). Manual review required: cd $VAULT_PATH && git status"
        exit 1
    fi
fi

# Case 2: Local changes exist - check for divergence
if [ "$REMOTE_HEAD" != "$MERGE_BASE" ] && [ "$LOCAL_HEAD" != "$MERGE_BASE" ]; then
    # Branches have diverged - CONFLICT
    alert "Branches diverged! Local and remote both have changes. Manual merge required: cd $VAULT_PATH && git status"
    exit 1
fi

# Remote is ahead but we have local changes - also a conflict
if [ "$REMOTE_HEAD" != "$MERGE_BASE" ] && [ "$LOCAL_HEAD" = "$MERGE_BASE" ]; then
    alert "Remote has changes and so do we locally. Manual merge required: cd $VAULT_PATH && git fetch && git status"
    exit 1
fi

# ============================================================================
# Safety Checks (before staging)
# ============================================================================

if [ "$CHANGED_FILES" -gt "$MAX_FILES_CHANGED" ]; then
    alert "$CHANGED_FILES files changed (max: $MAX_FILES_CHANGED). Manual review required: cd $VAULT_PATH && git status"
    exit 1
fi

# Check total lines changed (unstaged)
LINES_CHANGED=$(git diff --numstat 2>/dev/null | awk '{sum+=$1+$2} END {print sum+0}')
if [ "${LINES_CHANGED:-0}" -gt "$MAX_LINES_CHANGED" ]; then
    alert "${LINES_CHANGED} lines changed (max: $MAX_LINES_CHANGED). Possible large binary? Manual review required."
    exit 1
fi

# ============================================================================
# Stage, Commit, Push
# ============================================================================

git add -A

# Verify something to commit (git add might resolve to nothing)
if git diff --cached --quiet; then
    log "No changes after staging"
    exit 0
fi

# Generate commit message
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
SHORT_HOSTNAME="${HOSTNAME:-$(hostname -s 2>/dev/null || echo 'unknown')}"
SHORT_HOSTNAME="${SHORT_HOSTNAME%%.*}"
COMMIT_MSG="Auto-sync: $TIMESTAMP from $SHORT_HOSTNAME ($CHANGED_FILES files)"

if ! git commit -m "$COMMIT_MSG" --no-gpg-sign 2>&1 | while read -r line; do [ -n "$line" ] && log "commit: $line"; done; then
    alert "Commit failed - check $LOG_FILE"
    git reset 2>/dev/null || true  # Unstage on failure (no HEAD for empty repo compat)
    exit 1
fi

# Push with exponential backoff
for i in 1 2 3; do
    if git push origin "$BRANCH" 2>&1 | while read -r line; do [ -n "$line" ] && log "push: $line"; done; then
        log "SUCCESS: Pushed $CHANGED_FILES file(s) to origin/$BRANCH"
        exit 0
    fi
    sleep $((i * 2))  # 2s, 4s, 6s
done

alert "Push failed after 3 attempts. Check network/auth: cd $VAULT_PATH && git push"
exit 1
