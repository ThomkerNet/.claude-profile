#!/bin/bash
#
# DSC Library Test Script
# Demonstrates idempotent resource management
#
# Run twice - second run should show all "unchanged"
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/dsc.sh"

echo ""
echo "DSC Library Test"
echo "================"
echo "Platform: $DSC_PLATFORM"
echo "Package Manager: $DSC_PKG_MANAGER"
echo ""

# Test: Symlinks
echo "── Symlink Resources ──"
ensure_symlink "/tmp" "/tmp/dsc-test-link" "test-symlink"

# Test: Directory
echo ""
echo "── Directory Resources ──"
ensure_directory "/tmp/dsc-test-dir"

# Test: File Copy
echo ""
echo "── File Resources ──"
echo "test content" > /tmp/dsc-test-source.txt
ensure_file_copy "/tmp/dsc-test-source.txt" "/tmp/dsc-test-target.txt" "test-file"

# Test: Package (only test if already installed)
echo ""
echo "── Package Resources ──"
ensure_package "jq"
ensure_package "git"

# Summary
dsc_summary

# Cleanup
rm -f /tmp/dsc-test-link /tmp/dsc-test-source.txt /tmp/dsc-test-target.txt
rm -rf /tmp/dsc-test-dir

echo ""
echo "Test complete. Run again to verify idempotency."
