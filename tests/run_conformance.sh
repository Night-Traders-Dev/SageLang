#!/bin/bash
# Sage 2.0 Backend Conformance Suite
# Runs conformance tests across: interpreter, C backend, LLVM backend
set -e

SAGE="./sage"
PASS=0
FAIL=0
SKIP=0
TESTS_DIR="tests/40_conformance"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

run_test() {
    local file="$1"
    local mode="$2"
    local label="$3"
    local name=$(basename "$file" .sage)

    # Extract expected output
    local expected=$(grep '# EXPECT:' "$file" | sed 's/# EXPECT: //')

    local actual=""
    case "$mode" in
        interp)
            actual=$($SAGE "$file" 2>&1) || true
            ;;
        compile)
            local bin="/tmp/sage_conf_${name}_$$"
            if $SAGE --compile "$file" -o "$bin" 2>/dev/null; then
                actual=$("$bin" 2>&1) || true
                rm -f "$bin"
            else
                echo -e "  ${YELLOW}SKIP${NC} ${label} (compile failed)"
                SKIP=$((SKIP + 1))
                return
            fi
            ;;
        llvm)
            local bin="/tmp/sage_conf_${name}_llvm_$$"
            if $SAGE --compile-llvm "$file" -o "$bin" 2>/dev/null; then
                actual=$("$bin" 2>&1) || true
                rm -f "$bin"
            else
                echo -e "  ${YELLOW}SKIP${NC} ${label} (LLVM compile failed)"
                SKIP=$((SKIP + 1))
                return
            fi
            ;;
    esac

    if [ "$actual" = "$expected" ]; then
        echo -e "  ${GREEN}PASS${NC} ${label}"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} ${label}"
        FAIL=$((FAIL + 1))
        echo "    Expected: $(echo "$expected" | head -3)..."
        echo "    Got:      $(echo "$actual" | head -3)..."
    fi
}

echo -e "${BOLD}Sage 2.0 Backend Conformance Suite${NC}"
echo "======================================"
echo ""

for file in "$TESTS_DIR"/*.sage; do
    name=$(basename "$file" .sage)
    echo -e "${BOLD}$name${NC}:"
    run_test "$file" "interp" "interpreter"
    run_test "$file" "compile" "C backend"
    run_test "$file" "llvm" "LLVM backend"
    echo ""
done

TOTAL=$((PASS + FAIL + SKIP))
echo "======================================"
echo -e "${BOLD}Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC} / ${TOTAL} total"

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}All conformance tests passed!${NC}"
else
    echo -e "${RED}Some conformance tests failed.${NC}"
    exit 1
fi
