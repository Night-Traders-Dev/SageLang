#!/bin/bash
# ============================================================
#  SageLang Build Script
#  Build from C, run self-hosted tests, and install
# ============================================================

set -e

# --- Colors & Symbols ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

PASS="${GREEN}✓${RESET}"
FAIL="${RED}✗${RESET}"
ARROW="${CYAN}→${RESET}"
GEAR="${YELLOW}⚙${RESET}"
SAGE="${GREEN}🌿${RESET}"

cols=$(tput cols 2>/dev/null || echo 60)

banner() {
    printf "\n${BOLD}${CYAN}"
    printf '%.0s─' $(seq 1 "$cols")
    printf "\n  %s\n" "$1"
    printf '%.0s─' $(seq 1 "$cols")
    printf "${RESET}\n\n"
}

step() {
    printf "  ${GEAR} ${BOLD}%-40s${RESET}" "$1"
}

step_ok() {
    printf " ${PASS} ${GREEN}done${RESET} ${DIM}(%s)${RESET}\n" "$1"
}

step_fail() {
    printf " ${FAIL} ${RED}failed${RESET}\n"
    exit 1
}

section() {
    printf "\n  ${ARROW} ${BOLD}%s${RESET}\n" "$1"
}

# ============================================================
#  1. Clean previous builds
# ============================================================

banner "SageLang Build Pipeline"

section "Cleaning previous builds"

step "Removing build_sage/"
if [ -d build_sage ]; then
    rm -rf build_sage
    step_ok "removed"
else
    step_ok "already clean"
fi

step "Cleaning Make artifacts"
make clean > /dev/null 2>&1
step_ok "obj/ sage sage-lsp"

# ============================================================
#  2. Configure CMake (self-hosted mode)
# ============================================================

section "Configuring CMake (self-hosted Sage mode)"

step "Running cmake -DBUILD_SAGE=ON"
mkdir -p build_sage
cmake_output=$(cd build_sage && cmake -DBUILD_SAGE=ON .. 2>&1)
version=$(echo "$cmake_output" | grep -oP 'SageLang v\K[0-9.]+' | head -1)
compiler=$(echo "$cmake_output" | grep -oP 'C Compiler:\s+\K.*' | head -1)
step_ok "v${version:-0.13.0}"

printf "    ${DIM}Compiler:  %s${RESET}\n" "${compiler:-gcc}"
printf "    ${DIM}Mode:      Self-hosted (BUILD_SAGE=ON)${RESET}\n"
printf "    ${DIM}Host:      sage (C) → src/sage/sage.sage${RESET}\n"

# ============================================================
#  3. Build host interpreter
# ============================================================

section "Building C host interpreter"

step "Compiling sage (C sources)"
start_time=$SECONDS
build_output=$(cd build_sage && make -j"$(nproc)" sage 2>&1)
elapsed=$(( SECONDS - start_time ))
src_count=$(echo "$build_output" | grep -c "Building C object" || true)
step_ok "${src_count} files, ${elapsed}s"

# ============================================================
#  4. Run self-hosted tests
# ============================================================

banner "Self-Hosted Test Suite"

run_test() {
    local name="$1"
    local target="$2"
    local expect_pattern="$3"

    step "$name"
    output=$(cd build_sage && make "$target" 2>&1)
    if echo "$output" | grep -qE "$expect_pattern"; then
        count=$(echo "$output" | grep -oP '\d+/\d+' | tail -1)
        result=$(echo "$output" | grep -oP '\d+ passed' | tail -1)
        step_ok "${count:-ok} (${result:-passed})"
        return 0
    else
        step_fail
        return 1
    fi
}

total_pass=0
total_tests=0

section "Running tests through Sage interpreter"

if run_test "Lexer tests" "test_selfhost_lexer" "(All lexer tests passed|12/12)"; then
    total_pass=$((total_pass + 12))
fi
total_tests=$((total_tests + 12))

if run_test "Parser tests" "test_selfhost_parser" "(All tests passed|130/130)"; then
    total_pass=$((total_pass + 130))
fi
total_tests=$((total_tests + 130))

if run_test "Interpreter tests" "test_selfhost_interpreter" "(18 passed|Results: 18)"; then
    total_pass=$((total_pass + 18))
fi
total_tests=$((total_tests + 18))

if run_test "Bootstrap tests" "test_selfhost_bootstrap" "(All bootstrap tests passed|18/18)"; then
    total_pass=$((total_pass + 18))
fi
total_tests=$((total_tests + 18))

# --- Summary ---
printf "\n"
if [ "$total_pass" -eq "$total_tests" ]; then
    printf "  ${SAGE} ${BOLD}${GREEN}All %d/%d self-hosted tests passed${RESET}\n" "$total_pass" "$total_tests"
else
    printf "  ${FAIL} ${BOLD}${RED}%d/%d tests passed${RESET}\n" "$total_pass" "$total_tests"
    exit 1
fi

# ============================================================
#  5. Install (optional, requires sudo)
# ============================================================

banner "Installation"

if [ "$1" = "--install" ] || [ "$INSTALL" = "1" ]; then
    section "Building release binary for installation"
    step "Compiling sage via Make"
    make_output=$(make -j"$(nproc)" 2>&1)
    step_ok "sage + sage-lsp"

    section "Installing SageLang system-wide"
    printf "  ${GEAR} ${BOLD}Installing to /usr/local${RESET}\n"
    sudo make install 2>&1 | sed 's/^/    /'
    if [ "${PIPESTATUS[0]}" -eq 0 ]; then
        printf "  ${PASS} ${GREEN}Installed to /usr/local/bin/sage${RESET}\n"
    else
        printf "  ${FAIL} ${RED}Installation failed${RESET}\n"
        exit 1
    fi
else
    printf "  ${DIM}Skipping installation (pass --install or INSTALL=1 to enable)${RESET}\n"
    printf "  ${DIM}  ./build.sh --install${RESET}\n"
    printf "  ${DIM}  INSTALL=1 ./build.sh${RESET}\n"
fi

# ============================================================
#  Done
# ============================================================

banner "Build Complete"

printf "  ${SAGE} SageLang v${version:-0.13.0}\n"
printf "\n"
printf "  ${BOLD}Binaries:${RESET}\n"
printf "    ${ARROW} build_sage/sage         ${DIM}(C host interpreter)${RESET}\n"
printf "    ${ARROW} src/sage/sage.sage      ${DIM}(self-hosted bootstrap)${RESET}\n"
printf "\n"
printf "  ${BOLD}Usage:${RESET}\n"
printf "    ${DIM}\$ ${RESET}./build_sage/sage examples/hello.sage             ${DIM}# C interpreter${RESET}\n"
printf "    ${DIM}\$ ${RESET}cd src/sage && ../../build_sage/sage sage.sage app.sage  ${DIM}# Self-hosted${RESET}\n"
printf "    ${DIM}\$ ${RESET}make sage-boot FILE=app.sage                      ${DIM}# Via Make${RESET}\n"
printf "\n"
