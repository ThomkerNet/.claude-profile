#!/bin/bash
#
# setup-repos.sh
# Clones all repositories from linked GitHub organizations to ~/git-bnx
#
# Structure:
#   ~/git-bnx/
#     ├── TKN/        (ThomkerNet org)
#     ├── BNX/        (BoroughNexus org)
#     └── BriefHours/ (BriefHours org)
#
# Usage:
#   ./setup-repos.sh           # Clone/update all repos
#   ./setup-repos.sh --dry-run # Show what would be cloned
#   ./setup-repos.sh --org BNX # Clone only BoroughNexus repos
#
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
BASE_DIR="${HOME}/git-bnx"
DRY_RUN=false
FILTER_ORG=""

# Organization short names (for directory structure)
# Maps GitHub org names to short directory names
get_short_name() {
    case "$1" in
        ThomkerNet) echo "TKN" ;;
        BoroughNexus) echo "BNX" ;;
        BriefHours) echo "BriefHours" ;;
        *) echo "$1" ;;  # Default: use org name as-is
    esac
}

# Reverse: get GitHub org from short name
get_github_org() {
    case "$1" in
        TKN) echo "ThomkerNet" ;;
        BNX) echo "BoroughNexus" ;;
        BriefHours) echo "BriefHours" ;;
        *) echo "$1" ;;  # Default: assume it's already a GitHub org name
    esac
}

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_skip() { echo -e "${CYAN}[SKIP]${NC} $1"; }

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Clone all repositories from linked GitHub organizations.

Options:
  --dry-run       Show what would be cloned without making changes
  --org <name>    Only process specific org (TKN, BNX, BriefHours)
  --base <path>   Override base directory (default: ~/git-bnx)
  -h, --help      Show this help message

Organizations:
  TKN         ThomkerNet (personal/homelab)
  BNX         BoroughNexus (company)
  BriefHours  BriefHours (product)

Examples:
  $(basename "$0")                    # Clone all repos
  $(basename "$0") --dry-run          # Preview changes
  $(basename "$0") --org BNX          # Clone only BoroughNexus repos
  $(basename "$0") --base ~/projects  # Use different base directory
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --org)
            FILTER_ORG="$2"
            shift 2
            ;;
        --base)
            BASE_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check gh is available and authenticated
if ! command -v gh &>/dev/null; then
    log_error "GitHub CLI (gh) not found. Install with: brew install gh"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    log_error "Not authenticated with GitHub. Run: gh auth login"
    exit 1
fi

# Show current auth
CURRENT_USER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
log_info "Authenticated as: $CURRENT_USER"
echo ""

# Stats
CLONED=0
UPDATED=0
SKIPPED=0
FAILED=0

clone_or_update_repo() {
    local github_org="$1"
    local repo_name="$2"
    local target_dir="$3"
    local repo_path="${target_dir}/${repo_name}"

    if [[ -d "$repo_path/.git" ]]; then
        # Repo exists - pull updates
        if $DRY_RUN; then
            log_skip "$github_org/$repo_name (exists, would update)"
            ((SKIPPED++))
        else
            log_info "Updating $github_org/$repo_name..."
            if (cd "$repo_path" && git pull --ff-only 2>/dev/null); then
                log_success "$repo_name updated"
                ((UPDATED++))
            else
                log_warn "$repo_name has local changes, skipping update"
                ((SKIPPED++))
            fi
        fi
    else
        # Clone new repo
        if $DRY_RUN; then
            log_info "[DRY-RUN] Would clone: $github_org/$repo_name -> $repo_path"
            ((CLONED++))
        else
            log_info "Cloning $github_org/$repo_name..."
            if gh repo clone "$github_org/$repo_name" "$repo_path" -- --depth 1 2>/dev/null; then
                log_success "$repo_name cloned"
                ((CLONED++))
            else
                log_error "Failed to clone $repo_name"
                ((FAILED++))
            fi
        fi
    fi
}

process_org() {
    local short_name="$1"
    local github_org
    github_org=$(get_github_org "$short_name")
    local target_dir="${BASE_DIR}/${short_name}"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $short_name ($github_org)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Create target directory
    if ! $DRY_RUN; then
        mkdir -p "$target_dir"
    fi

    # Get all repos for this org
    local repos
    repos=$(gh api "orgs/$github_org/repos" --paginate --jq '.[].name' 2>/dev/null || \
            gh api "users/$github_org/repos" --paginate --jq '.[].name' 2>/dev/null || \
            echo "")

    if [[ -z "$repos" ]]; then
        log_warn "No repos found for $github_org (or no access)"
        return
    fi

    local repo_count
    repo_count=$(echo "$repos" | wc -l | tr -d ' ')
    log_info "Found $repo_count repositories"
    echo ""

    # Clone/update each repo
    while IFS= read -r repo_name; do
        [[ -z "$repo_name" ]] && continue
        clone_or_update_repo "$github_org" "$repo_name" "$target_dir"
    done <<< "$repos"
}

# Main
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              REPOSITORY SETUP                                 ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
log_info "Base directory: $BASE_DIR"
$DRY_RUN && log_warn "DRY RUN MODE - no changes will be made"

# Discover organizations from GitHub
log_info "Discovering organizations..."
DISCOVERED_ORGS=$(gh api user/orgs --jq '.[].login' 2>/dev/null || echo "")

if [[ -z "$DISCOVERED_ORGS" ]]; then
    log_warn "No organizations found for authenticated user"
    log_info "Will only clone personal repos if available"
fi

echo "Organizations found:"
for org in $DISCOVERED_ORGS; do
    short=$(get_short_name "$org")
    echo "  - $org -> $BASE_DIR/$short/"
done
echo ""

# Process organizations
if [[ -n "$FILTER_ORG" ]]; then
    # Resolve filter to GitHub org name
    github_org=$(get_github_org "$FILTER_ORG")
    if echo "$DISCOVERED_ORGS" | grep -q "^${github_org}$"; then
        process_org "$(get_short_name "$github_org")"
    else
        log_error "Org '$FILTER_ORG' not found in your accessible organizations"
        log_info "Available: $DISCOVERED_ORGS"
        exit 1
    fi
else
    for github_org in $DISCOVERED_ORGS; do
        short_name=$(get_short_name "$github_org")
        process_org "$short_name"
    done
fi

# Summary
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Summary${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Cloned:  ${GREEN}$CLONED${NC}"
echo -e "  Updated: ${BLUE}$UPDATED${NC}"
echo -e "  Skipped: ${YELLOW}$SKIPPED${NC}"
echo -e "  Failed:  ${RED}$FAILED${NC}"
echo ""

if $DRY_RUN; then
    log_info "Run without --dry-run to apply changes"
fi

exit $FAILED
