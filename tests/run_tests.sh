#!/usr/bin/env bash
# SageLang Test Suite Runner
# Runs all .sage test files and checks output against expected results

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SAGE="$SCRIPT_DIR/sage"
TESTS_DIR="$SCRIPT_DIR/tests"
PASS=0
FAIL=0
ERRORS=""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

run_test() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file" .sage)

    # Extract expected output from # EXPECT: comments at top of file
    local expected
    expected=$(grep '^# EXPECT: ' "$test_file" | sed 's/^# EXPECT: //')

    if [ -z "$expected" ]; then
        echo -e "  ${YELLOW}SKIP${NC} $test_name (no EXPECT comments)"
        return
    fi

    # Run the test from its directory (so module imports find sibling .sage files)
    local test_dir test_base actual exit_code
    test_dir=$(dirname "$test_file")
    test_base=$(basename "$test_file")
    actual=$(cd "$test_dir" && "$SAGE" "$test_base" 2>&1) && exit_code=0 || exit_code=$?

    if [ "$actual" = "$expected" ]; then
        echo -e "  ${GREEN}PASS${NC} $test_name"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${NC} $test_name"
        ERRORS="${ERRORS}\n${RED}--- FAIL: ${test_name} ---${NC}\n"
        ERRORS="${ERRORS}  Expected:\n$(echo "$expected" | sed 's/^/    /')\n"
        ERRORS="${ERRORS}  Got:\n$(echo "$actual" | sed 's/^/    /')\n"
        ((FAIL++))
    fi
}

run_error_test() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file" .sage)

    # Extract expected error substring from # EXPECT_ERROR: comments
    local expected_error
    expected_error=$(grep '^# EXPECT_ERROR: ' "$test_file" | sed 's/^# EXPECT_ERROR: //')

    if [ -z "$expected_error" ]; then
        echo -e "  ${YELLOW}SKIP${NC} $test_name (no EXPECT_ERROR comment)"
        return
    fi

    local test_dir test_base output exit_code
    test_dir=$(dirname "$test_file")
    test_base=$(basename "$test_file")
    output=$(cd "$test_dir" && "$SAGE" "$test_base" 2>&1) && exit_code=0 || exit_code=$?

    if echo "$output" | grep -qF "$expected_error"; then
        echo -e "  ${GREEN}PASS${NC} $test_name"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${NC} $test_name"
        ERRORS="${ERRORS}\n${RED}--- FAIL: ${test_name} ---${NC}\n"
        ERRORS="${ERRORS}  Expected error containing: ${expected_error}\n"
        ERRORS="${ERRORS}  Got:\n$(echo "$output" | sed 's/^/    /')\n"
        ((FAIL++))
    fi
}

echo -e "${BOLD}${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║     SageLang Test Suite                ║${NC}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# Run each category
for category_dir in "$TESTS_DIR"/*/; do
    [ -d "$category_dir" ] || continue
    category=$(basename "$category_dir")
    echo -e "${BOLD}${CYAN}[$category]${NC}"

    for test_file in "$category_dir"/*.sage; do
        [ -f "$test_file" ] || continue
        if grep -q '^# EXPECT_ERROR: ' "$test_file"; then
            run_error_test "$test_file"
        else
            run_test "$test_file"
        fi
    done
    echo ""
done

# Also run top-level test files
for test_file in "$TESTS_DIR"/*.sage; do
    [ -f "$test_file" ] || continue
    if grep -q '^# EXPECT_ERROR: ' "$test_file"; then
        run_error_test "$test_file"
    else
        run_test "$test_file"
    fi
done

# Summary
echo -e "${BOLD}════════════════════════════════════════${NC}"
TOTAL=$((PASS + FAIL))
echo -e "${BOLD}Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC} / ${TOTAL} total"

if [ -n "$ERRORS" ]; then
    echo ""
    echo -e "${BOLD}Failures:${NC}"
    echo -e "$ERRORS"
fi

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
echo -e "${GREEN}${BOLD}All tests passed!${NC}"
