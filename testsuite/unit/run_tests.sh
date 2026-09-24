#!/usr/bin/env bash
# SageLang Test Suite Runner
# Runs all .sage test files and checks output against expected results

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SAGE="${SAGE:-$SCRIPT_DIR/../core/sage}"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
# Prefer local lib/ over any installed system copy
export SAGE_PATH="$SCRIPT_DIR/../core/lib${SAGE_PATH:+:$SAGE_PATH}"
PASS=0
FAIL=0
ERRORS=""
FILTER="${SAGE_TEST_FILTER:-}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --filter)
            [ "$#" -ge 2 ] || { printf 'Missing value for --filter\n' >&2; exit 2; }
            FILTER="$2"
            shift 2
            ;;
        --filter=*)
            FILTER="${1#--filter=}"
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            FILTER="$1"
            shift
            break
            ;;
    esac
done
FILTER_MATCHED=0

matches_filter() {
    local value="$1"
    if [ -z "$FILTER" ]; then
        return 0
    fi
    case "$value" in
        *"$FILTER"*) FILTER_MATCHED=1; return 0 ;;
        *) return 1 ;;
    esac
}

smoke_output_failed() {
    local output="$1"
    [[ "$output" =~ (^|[[:space:]])[1-9][0-9]*[[:space:]]+(failed|failures)([[:space:]]|$) ]] && return 0
    [[ "$output" =~ (^|[[:space:]])FAIL([[:space:]]|$) ]] && return 0
    return 1
}

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
    TEST_OUTPUT=""
    TEST_EXIT_CODE=0
    run_mode=$(grep '^# RUN: ' "$test_file" | head -1 | sed 's/^# RUN: //')
    test_dir=$(dirname "$test_file")
    test_base=$(basename "$test_file")

    case "$run_mode" in
        ""|"run")
            if [[ "$test_dir" == *_lib ]] || [[ "$test_dir" == *_stdlib ]] || [[ "$test_dir" == "$TESTS_DIR" ]]; then
                TEST_OUTPUT=$(cd "$SCRIPT_DIR/../core" && "$SAGE" "$test_file" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
            else
                TEST_OUTPUT=$(cd "$test_dir" && "$SAGE" "$test_base" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
            fi
            ;;
        "emit-c")
            mkdir -p "$SCRIPT_DIR/.tmp"
            tmp_path=$(mktemp "$SCRIPT_DIR/.tmp/test_emit_XXXXXX.c")
            TEST_OUTPUT=$(cd "$SCRIPT_DIR/../core" && "$SAGE" --emit-c "$test_file" -o "$tmp_path" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
            rm -f "$tmp_path"
            ;;
        "compile")
            mkdir -p "$SCRIPT_DIR/.tmp"
            tmp_path=$(mktemp "$SCRIPT_DIR/.tmp/test_compile_XXXXXX.bin")
            TEST_OUTPUT=$(cd "$SCRIPT_DIR/../core" && "$SAGE" --compile "$test_file" -o "$tmp_path" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
            rm -f "$tmp_path"
            ;;
        "compile-run")
            mkdir -p "$SCRIPT_DIR/.tmp"
            tmp_path=$(mktemp "$SCRIPT_DIR/.tmp/test_compile_run_XXXXXX.bin")
            local compile_output run_output run_cwd
            compile_output=$(cd "$SCRIPT_DIR/../core" && "$SAGE" --compile "$test_file" -o "$tmp_path" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
            if [ "$TEST_EXIT_CODE" -eq 0 ]; then
                if [[ "$test_dir" == *_lib ]] || [[ "$test_dir" == *_stdlib ]] || [[ "$test_dir" == "$TESTS_DIR" ]]; then
                    run_cwd="$SCRIPT_DIR"
                else
                    run_cwd="$test_dir"
                fi
                run_output=$(cd "$run_cwd" && "$tmp_path" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
                TEST_OUTPUT="$run_output"
            else
                TEST_OUTPUT="$compile_output"
            fi
            rm -f "$tmp_path"
            ;;
        "bytecode-run")
            if [[ "$test_dir" == *_lib ]] || [[ "$test_dir" == *_stdlib ]] || [[ "$test_dir" == "$TESTS_DIR" ]]; then
                TEST_OUTPUT=$(cd "$SCRIPT_DIR/../core" && "$SAGE" --runtime bytecode "$test_file" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
            else
                TEST_OUTPUT=$(cd "$test_dir" && "$SAGE" --runtime bytecode "$test_base" 2>&1) && TEST_EXIT_CODE=0 || TEST_EXIT_CODE=$?
            fi
            ;;
        *)
            TEST_OUTPUT="Unknown # RUN mode '$run_mode' in $test_file"
            TEST_EXIT_CODE=2
            ;;
    esac
}

run_test() {
    local test_file="$1"
    local test_name expected actual has_expect
    test_name=$(basename "$test_file" .sage)
    if grep -q '^# EXPECT: ' "$test_file"; then
        has_expect=1
    else
        has_expect=0
    fi
    expected=$(grep '^# EXPECT: ' "$test_file" | sed 's/^# EXPECT: //')

    capture_test_output "$test_file"
    actual="$TEST_OUTPUT"

    if [ "$has_expect" -eq 0 ]; then
        if [ "$TEST_EXIT_CODE" -eq 0 ] && ! smoke_output_failed "$actual"; then
            echo -e "  ${GREEN}PASS${NC} $test_name (no EXPECT; exit status)"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} $test_name"
            ERRORS="${ERRORS}\n${RED}--- FAIL: ${test_name} ---${NC}\n"
            ERRORS="${ERRORS}  Exit status: ${TEST_EXIT_CODE}\n"
            ERRORS="${ERRORS}  Got:\n$(printf '%s\n' "$actual" | sed 's/^/    /')\n"
            FAIL=$((FAIL + 1))
        fi
        return 0
    fi

    if [ "$actual" = "$expected" ] && { [ "$TEST_EXIT_CODE" -eq 0 ] || [[ "$expected" == error:* ]]; }; then
        echo -e "  ${GREEN}PASS${NC} $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $test_name"
        ERRORS="${ERRORS}\n${RED}--- FAIL: ${test_name} ---${NC}\n"
        ERRORS="${ERRORS}  Exit status: ${TEST_EXIT_CODE}\n"
        ERRORS="${ERRORS}  Expected:\n$(printf '%s\n' "$expected" | sed 's/^/    /')\n"
        ERRORS="${ERRORS}  Got:\n$(printf '%s\n' "$actual" | sed 's/^/    /')\n"
        FAIL=$((FAIL + 1))
    fi
    return 0
}

run_error_test() {
    local test_file="$1"
    local test_name output
    test_name=$(basename "$test_file" .sage)

    local expected_errors=()
    mapfile -t expected_errors < <(grep '^# EXPECT_ERROR: ' "$test_file" | sed 's/^# EXPECT_ERROR: //')

    if [ "${#expected_errors[@]}" -eq 0 ]; then
        return 0
    fi

    local missing=()
    capture_test_output "$test_file"
    output="$TEST_OUTPUT"
    if [ "$TEST_EXIT_CODE" -eq 0 ]; then
        missing+=("command exited successfully")
    fi
    for expected_error in "${expected_errors[@]}"; do
        [[ "$output" == *"$expected_error"* ]] || missing+=("$expected_error")
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        echo -e "  ${GREEN}PASS${NC} $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $test_name"
        ERRORS="${ERRORS}\n${RED}--- FAIL: ${test_name} ---${NC}\n"
        ERRORS="${ERRORS}  Exit status: ${TEST_EXIT_CODE}\n"
        for expected_error in "${missing[@]}"; do
            ERRORS="${ERRORS}  Missing error text: ${expected_error}\n"
        done
        ERRORS="${ERRORS}  Got:\n$(printf '%s\n' "$output" | sed 's/^/    /')\n"
        FAIL=$((FAIL + 1))
    fi
    return 0
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
        matches_filter "$test_file" || continue
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
    matches_filter "$test_file" || continue
    if grep -q '^# EXPECT_ERROR: ' "$test_file"; then
        run_error_test "$test_file"
    else
        run_test "$test_file"
    fi
done

# Summary
if [ -n "$FILTER" ] && [ "$FILTER_MATCHED" -eq 0 ]; then
    echo -e "  ${YELLOW}SKIP${NC} filter matched no tests: $FILTER"
    exit 2
fi
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
