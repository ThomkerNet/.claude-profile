#!/bin/bash
# Tests for bw-tkn wrapper
# Run: bash bw-tkn.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BW_TKN="$SCRIPT_DIR/bw-tkn"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    ((TESTS_FAILED++))
    echo -e "${RED}✗${NC} $1"
    [[ -n "${2:-}" ]] && echo "  $2"
}

skip() {
    echo -e "${YELLOW}○${NC} $1 (skipped)"
}

# =============================================================================
# Unit Tests (don't require bw CLI or network)
# =============================================================================

echo ""
echo "=== Unit Tests ==="
echo ""

# Test: Script is executable
((TESTS_RUN++))
if [[ -x "$BW_TKN" ]]; then
    pass "Script is executable"
else
    fail "Script is not executable"
fi

# Test: Script has proper shebang
((TESTS_RUN++))
if head -1 "$BW_TKN" | grep -q '^#!/bin/bash'; then
    pass "Script has bash shebang"
else
    fail "Script missing bash shebang"
fi

# Test: Script uses strict mode
((TESTS_RUN++))
if grep -q 'set -euo pipefail' "$BW_TKN"; then
    pass "Script uses strict mode"
else
    fail "Script missing strict mode"
fi

# Test: Cleanup trap is defined
((TESTS_RUN++))
if grep -q 'trap cleanup EXIT INT TERM' "$BW_TKN"; then
    pass "Cleanup trap is defined"
else
    fail "Cleanup trap missing"
fi

# Test: Server config failure is fatal (not just warning)
((TESTS_RUN++))
if grep -q 'Error: Failed to configure server URL' "$BW_TKN" && \
   grep -A1 'Failed to configure server URL' "$BW_TKN" | grep -q 'exit 1'; then
    pass "Server config failure is fatal"
else
    fail "Server config failure should be fatal, not warning"
fi

# Test: Password file is overwritten before deletion
((TESTS_RUN++))
if grep -q 'dd if=/dev/zero' "$BW_TKN"; then
    pass "Password file is overwritten before deletion"
else
    fail "Password file should be overwritten before deletion"
fi

# Test: Session token format is validated
((TESTS_RUN++))
if grep -q 'Invalid session token format' "$BW_TKN"; then
    pass "Session token format is validated"
else
    fail "Session token format should be validated"
fi

# Test: Email regex is proper (not just @ check)
((TESTS_RUN++))
if grep -q '\^.\+@.\+\\.' "$BW_TKN"; then
    pass "Email detection uses proper regex"
else
    fail "Email detection should use proper regex, not just @ check"
fi

# Test: TTY check is readable+writable
((TESTS_RUN++))
if grep -q '\-r /dev/tty' "$BW_TKN" && grep -q '\-w /dev/tty' "$BW_TKN"; then
    pass "TTY check verifies read+write access"
else
    fail "TTY check should verify both read and write access"
fi

# =============================================================================
# Integration Tests (require bw CLI)
# =============================================================================

echo ""
echo "=== Integration Tests ==="
echo ""

# Check if bw is available
if ! command -v bw >/dev/null 2>&1; then
    skip "bw CLI not found - skipping integration tests"
else
    # Test: Script runs without errors for --help
    ((TESTS_RUN++))
    if "$BW_TKN" --help >/dev/null 2>&1; then
        pass "Script passes through --help"
    else
        fail "Script should pass through --help"
    fi

    # Test: Script runs status command
    ((TESTS_RUN++))
    if "$BW_TKN" status >/dev/null 2>&1; then
        pass "Script passes through status"
    else
        fail "Script should pass through status"
    fi

    # Test: Script configures correct server
    ((TESTS_RUN++))
    status=$("$BW_TKN" status 2>/dev/null || true)
    if echo "$status" | grep -q 'vaultwarden.thomker.net'; then
        pass "Script configures correct server"
    else
        fail "Script should configure vaultwarden.thomker.net"
    fi

    # Test: Script uses isolated data directory
    ((TESTS_RUN++))
    data_dir="$HOME/.config/bitwarden-cli/tkn"
    if [[ -d "$data_dir" ]]; then
        pass "Script creates isolated data directory"
    else
        fail "Script should create isolated data directory at $data_dir"
    fi
fi

# =============================================================================
# has_arg function tests (extracted and tested separately)
# =============================================================================

echo ""
echo "=== has_arg Function Tests ==="
echo ""

# Extract and test has_arg function
has_arg() {
    local needle="$1"
    shift
    for arg in "$@"; do
        [[ "$arg" == "$needle" ]] && return 0
    done
    return 1
}

((TESTS_RUN++))
if has_arg "--raw" "unlock" "--raw"; then
    pass "has_arg finds --raw"
else
    fail "has_arg should find --raw"
fi

((TESTS_RUN++))
if ! has_arg "--raw" "unlock"; then
    pass "has_arg returns false when not found"
else
    fail "has_arg should return false when arg not present"
fi

((TESTS_RUN++))
if ! has_arg "--raw" "unlock" "--rawish"; then
    pass "has_arg doesn't match partial (--rawish)"
else
    fail "has_arg should not match --rawish for --raw"
fi

((TESTS_RUN++))
if ! has_arg "--raw" "unlock" "foo--rawbar"; then
    pass "has_arg doesn't match substring"
else
    fail "has_arg should not match substring containing --raw"
fi

# =============================================================================
# Email regex tests
# =============================================================================

echo ""
echo "=== Email Regex Tests ==="
echo ""

email_matches() {
    [[ "$1" =~ ^[^@]+@[^@]+\.[^@]+$ ]]
}

((TESTS_RUN++))
if email_matches "user@example.com"; then
    pass "Regex matches valid email"
else
    fail "Regex should match user@example.com"
fi

((TESTS_RUN++))
if email_matches "user@mail.example.com"; then
    pass "Regex matches subdomain email"
else
    fail "Regex should match user@mail.example.com"
fi

((TESTS_RUN++))
if ! email_matches "userexample.com"; then
    pass "Regex rejects email without @"
else
    fail "Regex should reject email without @"
fi

((TESTS_RUN++))
if ! email_matches "user@examplecom"; then
    pass "Regex rejects email without dot in domain"
else
    fail "Regex should reject email without dot in domain"
fi

((TESTS_RUN++))
if ! email_matches "--sso@thing"; then
    pass "Regex rejects flag-like strings with @"
else
    fail "Regex should reject --sso@thing as not an email"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=== Test Summary ==="
echo ""
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
