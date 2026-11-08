#!/bin/sh
# run_tests.sh - Master automated test runner for OSTEON framework.
# Executes all test suites and generates unified pass/fail results.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

echo "========================================================================"
echo "OSTEON Framework — Automated Test Harness"
echo "Repository: $REPO_ROOT"
echo "Date:       $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "========================================================================"
echo ""

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

run_suite() {
    _name="$1"
    _cmd="$2"
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    echo "------------------------------------------------------------------------"
    echo "Running Suite: $_name"
    echo "------------------------------------------------------------------------"
    set +e
    sh -c "$_cmd"
    _rc=$?
    set -e
    if [ "$_rc" -eq 0 ]; then
        echo "[+] SUITE PASSED: $_name"
        PASSED_SUITES=$((PASSED_SUITES + 1))
    else
        echo "[-] SUITE FAILED (exit code $_rc): $_name"
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
    echo ""
}

# Suite 1: YAML key-ordering resilience
run_suite "YAML Manifest Key-Order Resilience" "$SCRIPT_DIR/test_yaml_key_order.sh"

# Suite 2: CDI mathematical boundaries & formats
run_suite "Context Decay Index (CDI) Math & Formats" "$SCRIPT_DIR/test_cdi_math.sh"

# Suite 3: Linter safety, spaces & unicode
run_suite "Linter Safety & Path Escaping" "$SCRIPT_DIR/test_linter_safety.sh"

# Suite 4: Upstream Core Selftest Harness
run_suite "Core Scaffold Hooks Selftest" "(cd \"$REPO_ROOT/plugins/osteon/scaffold/template/.claude/hooks\" && ./selftest.sh)"

echo "========================================================================"
echo "Test Execution Summary"
echo "========================================================================"
echo "Total Suites:  $TOTAL_SUITES"
echo "Passed Suites: $PASSED_SUITES"
echo "Failed Suites: $FAILED_SUITES"
echo "========================================================================"

if [ "$FAILED_SUITES" -gt 0 ]; then
    echo "VERDICT: FAIL"
    exit 1
fi

echo "VERDICT: ALL TESTS PASSED"
exit 0
