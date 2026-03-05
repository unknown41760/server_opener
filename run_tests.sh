#!/bin/bash

# =============================================================================
# Quick Test Runner
# =============================================================================
# Simple wrapper to run both hardening and tests in sequence
# Usage: sudo ./run_tests.sh
# =============================================================================

set -e

echo "========================================"
echo "Server Hardening Test Runner"
echo "========================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Check if scripts exist
if [ ! -f "server_hardening.sh" ]; then
    echo "ERROR: server_hardening.sh not found in current directory"
    exit 1
fi

if [ ! -f "test_hardening.sh" ]; then
    echo "ERROR: test_hardening.sh not found in current directory"
    exit 1
fi

echo "This will:"
echo "  1. Run server_hardening.sh"
echo "  2. Run test_hardening.sh to verify everything"
echo ""
read -p "Continue? (yes/no): " -r

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "========================================"
echo "STEP 1: Running Server Hardening Script"
echo "========================================"
echo ""

chmod +x server_hardening.sh
./server_hardening.sh

if [ $? -ne 0 ]; then
    echo "ERROR: Hardening script failed"
    exit 1
fi

echo ""
echo "========================================"
echo "STEP 2: Running Test Suite"
echo "========================================"
echo ""

chmod +x test_hardening.sh
./test_hardening.sh

TEST_RESULT=$?

echo ""
echo "========================================"
echo "COMPLETE"
echo "========================================"
echo ""

if [ $TEST_RESULT -eq 0 ]; then
    echo "✓ All tests passed!"
    echo ""
    echo "Your server is hardened and ready for production."
else
    echo "⚠ Some tests failed."
    echo ""
    echo "Review the test output above for details."
fi

echo ""
echo "Reports are available in /root/"
ls -lh /root/*.txt /var/log/*.log 2>/dev/null | grep -E "(hardening|security)" || true
