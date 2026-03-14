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

capture_test_output() {
    local test_file="$1"
    local run_mode test_dir test_base tmp_path
    run_mode=$(grep '^# RUN: ' "$test_file" | head -1 | sed 's/^# RUN: //')
    test_dir=$(dirname "$test_file")
    test_base=$(basename "$test_file")

    case "$run_mode" in
        ""|"run")
            if [[ "$test_dir" == *_lib ]] || [[ "$test_dir" == "$TESTS_DIR" ]]; then
                TEST_OUTPUT=$(cd "$SCRIPT_DIR" && "$SAGE" "$test_file" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
            else
                TEST_OUTPUT=$(cd "$test_dir" && "$SAGE" "$test_base" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
            fi
            ;;
        "emit-c")
            mkdir -p "$SCRIPT_DIR/.tmp"
            tmp_path=$(mktemp "$SCRIPT_DIR/.tmp/test_emit_XXXXXX.c")
            TEST_OUTPUT=$(cd "$SCRIPT_DIR" && "$SAGE" --emit-c "$test_file" -o "$tmp_path" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
            rm -f "$tmp_path"
            ;;
        "compile")
            mkdir -p "$SCRIPT_DIR/.tmp"
            tmp_path=$(mktemp "$SCRIPT_DIR/.tmp/test_compile_XXXXXX.bin")
            TEST_OUTPUT=$(cd "$SCRIPT_DIR" && "$SAGE" --compile "$test_file" -o "$tmp_path" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
            rm -f "$tmp_path"
            ;;
        *)
            TEST_OUTPUT="Unknown # RUN mode '$run_mode' in $test_file"
            TEST_EXIT_CODE=2
            ;;
    esac
}

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

    local actual
    capture_test_output "$test_file"
    actual="$TEST_OUTPUT"

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

    local expected_errors=()
    mapfile -t expected_errors < <(grep '^# EXPECT_ERROR: ' "$test_file" | sed 's/^# EXPECT_ERROR: //')

    if [ "${#expected_errors[@]}" -eq 0 ]; then
        echo -e "  ${YELLOW}SKIP${NC} $test_name (no EXPECT_ERROR comment)"
        return
    fi

    local output missing=()
    capture_test_output "$test_file"
    output="$TEST_OUTPUT"

    for expected_error in "${expected_errors[@]}"; do
        if ! echo "$output" | grep -qF -- "$expected_error"; then
            missing+=("$expected_error")
        fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        echo -e "  ${GREEN}PASS${NC} $test_name"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${NC} $test_name"
        ERRORS="${ERRORS}\n${RED}--- FAIL: ${test_name} ---${NC}\n"
        for expected_error in "${missing[@]}"; do
            ERRORS="${ERRORS}  Missing error text: ${expected_error}\n"
        done
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

# Also run top-level test files (from project root so lib/ imports resolve)
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
