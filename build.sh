#!/bin/bash
# ============================================================
#  SageLang Build Script
#  Comprehensive build, test, and install pipeline
#  Usage: ./build.sh [--install] [--skip-tests] [--make-only]
# ============================================================

set -euo pipefail

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
WARN="${YELLOW}!${RESET}"
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
    printf "  ${GEAR} ${BOLD}%-45s${RESET}" "$1"
}

step_ok() {
    printf " ${PASS} ${GREEN}done${RESET} ${DIM}(%s)${RESET}\n" "$1"
}

step_warn() {
    printf " ${WARN} ${YELLOW}%s${RESET}\n" "$1"
}

step_fail() {
    printf " ${FAIL} ${RED}%s${RESET}\n" "${1:-failed}"
    exit 1
}

section() {
    printf "\n  ${ARROW} ${BOLD}%s${RESET}\n" "$1"
}

# --- Parse arguments ---
DO_INSTALL=0
SKIP_TESTS=0
MAKE_ONLY=0

for arg in "$@"; do
    case "$arg" in
        --install)    DO_INSTALL=1 ;;
        --skip-tests) SKIP_TESTS=1 ;;
        --make-only)  MAKE_ONLY=1 ;;
        --help|-h)
            echo "Usage: ./build.sh [options]"
            echo "  --install      Install to /usr/local after building"
            echo "  --skip-tests   Skip test suite"
            echo "  --make-only    Use Make instead of CMake"
            echo "  --help         Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg (use --help)" >&2
            exit 1
            ;;
    esac
done

# ============================================================
#  0. Check dependencies
# ============================================================

banner "SageLang Build Pipeline"

section "Checking dependencies"

check_dep() {
    local name="$1"
    local cmd="$2"
    step "Checking $name"
    if command -v "$cmd" > /dev/null 2>&1; then
        local ver
        ver=$("$cmd" --version 2>&1 | head -1 | sed 's/.*version //' | sed 's/ .*//' || echo "unknown")
        step_ok "$ver"
        return 0
    else
        step_warn "not found"
        return 1
    fi
}

MISSING=0
check_dep "C compiler (gcc)" "gcc" || MISSING=1
check_dep "Make" "make" || MISSING=1

# Optional deps
HAS_CMAKE=0
check_dep "CMake" "cmake" && HAS_CMAKE=1 || true
HAS_GLSLC=0
check_dep "GLSL compiler (glslc)" "glslc" && HAS_GLSLC=1 || true
HAS_VULKAN=0
step "Checking Vulkan SDK"
if pkg-config --exists vulkan 2>/dev/null; then
    step_ok "$(pkg-config --modversion vulkan)"
    HAS_VULKAN=1
else
    step_warn "not found (GPU features disabled)"
fi
HAS_GLFW=0
step "Checking GLFW"
if pkg-config --exists glfw3 2>/dev/null; then
    step_ok "$(pkg-config --modversion glfw3)"
    HAS_GLFW=1
else
    step_warn "not found (windowed mode disabled)"
fi

step "Checking libcurl"
if pkg-config --exists libcurl 2>/dev/null; then
    step_ok "$(pkg-config --modversion libcurl)"
else
    step_warn "not found (HTTP module disabled)"
fi

step "Checking OpenSSL"
if pkg-config --exists openssl 2>/dev/null; then
    step_ok "$(pkg-config --modversion openssl)"
else
    step_warn "not found (SSL module disabled)"
fi

if [ "$MISSING" -eq 1 ]; then
    printf "\n  ${FAIL} ${RED}Missing required dependencies. Install gcc and make.${RESET}\n"
    exit 1
fi

# ============================================================
#  1. Clean previous builds
# ============================================================

section "Cleaning previous builds"

step "Removing old build artifacts"
if [ -d build_sage ]; then
    rm -rf build_sage
fi
make clean > /dev/null 2>&1 || true
step_ok "clean"

# ============================================================
#  2. Compile shaders (if glslc available)
# ============================================================

if [ "$HAS_GLSLC" -eq 1 ] && [ -d examples/shaders ]; then
    section "Compiling GLSL shaders to SPIR-V"
    step "Compiling shaders"
    shader_count=0
    shader_fail=0
    for f in examples/shaders/*.vert examples/shaders/*.frag examples/shaders/*.comp; do
        [ -f "$f" ] || continue
        if glslc "$f" -o "$f.spv" 2>/dev/null; then
            shader_count=$((shader_count + 1))
        else
            printf "\n    ${FAIL} Failed: %s\n" "$f"
            shader_fail=$((shader_fail + 1))
        fi
    done
    if [ "$shader_fail" -eq 0 ]; then
        step_ok "$shader_count modules"
    else
        step_warn "$shader_count ok, $shader_fail failed"
    fi
fi

# ============================================================
#  3. Build
# ============================================================

if [ "$MAKE_ONLY" -eq 1 ] || [ "$HAS_CMAKE" -eq 0 ]; then
    # Pure Make build
    section "Building with Make"

    step "Compiling sage (C sources)"
    start_time=$SECONDS
    if ! build_output=$(make -j"$(nproc)" 2>&1); then
        printf "\n"
        echo "$build_output" | tail -20
        step_fail "compilation failed"
    fi
    elapsed=$(( SECONDS - start_time ))
    src_count=$(echo "$build_output" | grep -c "Compiled:" || echo "?")
    step_ok "${src_count} files, ${elapsed}s"

    SAGE_BIN="./sage"
    SAGE_LSP_BIN="./sage-lsp"
else
    # CMake build (self-hosted mode)
    section "Configuring CMake (self-hosted Sage mode)"

    step "Running cmake -DBUILD_SAGE=ON"
    mkdir -p build_sage
    if ! cmake_output=$(cd build_sage && cmake -DBUILD_SAGE=ON .. 2>&1); then
        printf "\n"
        echo "$cmake_output" | tail -20
        step_fail "CMake configuration failed"
    fi
    version=$(echo "$cmake_output" | grep -oP 'SageLang v\K[0-9.]+' 2>/dev/null | head -1 || echo "")
    compiler=$(echo "$cmake_output" | grep -oP 'C Compiler:\s+\K.*' 2>/dev/null | head -1 || echo "gcc")
    step_ok "v${version:-0.15.0}"

    printf "    ${DIM}Compiler:  %s${RESET}\n" "${compiler:-gcc}"
    printf "    ${DIM}Mode:      Self-hosted (BUILD_SAGE=ON)${RESET}\n"

    section "Building C host interpreter"

    step "Compiling sage (C sources)"
    start_time=$SECONDS
    if ! build_output=$(cd build_sage && make -j"$(nproc)" sage 2>&1); then
        printf "\n"
        echo "$build_output" | tail -20
        step_fail "compilation failed"
    fi
    elapsed=$(( SECONDS - start_time ))
    src_count=$(echo "$build_output" | grep -c "Building C object" || echo "?")
    step_ok "${src_count} files, ${elapsed}s"

    SAGE_BIN="./build_sage/sage"
    SAGE_LSP_BIN="./build_sage/sage-lsp"
fi

# Verify binary exists
step "Verifying binary"
if [ -x "$SAGE_BIN" ]; then
    bin_size=$(du -h "$SAGE_BIN" | cut -f1)
    step_ok "$SAGE_BIN ($bin_size)"
else
    step_fail "binary not found: $SAGE_BIN"
fi

# ============================================================
#  4. Run tests
# ============================================================

if [ "$SKIP_TESTS" -eq 0 ]; then
    banner "Test Suite"

    total_pass=0
    total_fail=0
    total_suites=0

    run_test() {
        local name="$1"
        local cmd="$2"
        local expect_pattern="$3"

        step "$name"
        total_suites=$((total_suites + 1))
        if output=$(eval "$cmd" 2>&1); then
            if echo "$output" | grep -qE "$expect_pattern"; then
                # Extract pass count
                local pass_count
                pass_count=$(echo "$output" | grep -oP '\d+ passed' | tail -1 | grep -oP '\d+' || echo "0")
                step_ok "${pass_count} passed"
                total_pass=$((total_pass + pass_count))
                return 0
            else
                step_warn "pattern not matched"
                echo "$output" | tail -3 | sed 's/^/    /'
                return 1
            fi
        else
            local err_lines
            err_lines=$(echo "$output" | grep -i "error\|fail" | head -3)
            if [ -n "$err_lines" ]; then
                step_warn "errors found"
                echo "$err_lines" | sed 's/^/    /'
            else
                step_warn "exit code $?"
            fi
            return 1
        fi
    }

    section "C Interpreter Tests"
    run_test "Interpreter tests (144)" "make test 2>&1" "(All \d+ tests passed|PASS)" || total_fail=$((total_fail + 1))

    section "Self-Hosted Tests"

    # Run the full make test-selfhost which covers ALL suites
    step "Full self-hosted suite"
    if output=$(make test-selfhost 2>&1); then
        if echo "$output" | grep -q "All self-hosted tests complete"; then
            # Count all passed tests
            suite_total=$(echo "$output" | grep -oP '\d+ passed' | awk '{sum+=$1} END{print sum+0}')
            step_ok "${suite_total} tests across all suites"
            total_pass=$((total_pass + suite_total))
        else
            step_warn "incomplete"
            echo "$output" | tail -5 | sed 's/^/    /'
            total_fail=$((total_fail + 1))
        fi
    else
        step_warn "test-selfhost failed"
        echo "$output" | grep "FAIL" | head -5 | sed 's/^/    /'
        total_fail=$((total_fail + 1))
    fi

    # --- Summary ---
    printf "\n"
    if [ "$total_fail" -eq 0 ]; then
        printf "  ${SAGE} ${BOLD}${GREEN}All tests passed (%d tests across %d suites)${RESET}\n" "$total_pass" "$total_suites"
    else
        printf "  ${FAIL} ${BOLD}${RED}%d suite(s) had failures (%d tests passed)${RESET}\n" "$total_fail" "$total_pass"
        exit 1
    fi
else
    printf "\n  ${DIM}Tests skipped (--skip-tests)${RESET}\n"
fi

# ============================================================
#  5. Install (optional)
# ============================================================

if [ "$DO_INSTALL" -eq 1 ]; then
    banner "Installation"

    section "Building release binary for installation"
    step "Compiling sage via Make (release)"
    if ! make_output=$(make -j"$(nproc)" 2>&1); then
        step_fail "Make build failed"
    fi
    step_ok "sage + sage-lsp"

    section "Installing SageLang system-wide"
    printf "  ${GEAR} ${BOLD}Installing to /usr/local${RESET}\n"
    if sudo make install 2>&1 | sed 's/^/    /'; then
        printf "  ${PASS} ${GREEN}Installed to /usr/local/bin/sage${RESET}\n"
    else
        step_fail "Installation failed (sudo required)"
    fi
fi

# ============================================================
#  Done
# ============================================================

banner "Build Complete"

printf "  ${SAGE} SageLang v${version:-0.15.0}\n"
printf "\n"
printf "  ${BOLD}Binaries:${RESET}\n"
printf "    ${ARROW} %-30s ${DIM}(C interpreter)${RESET}\n" "$SAGE_BIN"
if [ -x "$SAGE_LSP_BIN" ] 2>/dev/null; then
    printf "    ${ARROW} %-30s ${DIM}(LSP server)${RESET}\n" "$SAGE_LSP_BIN"
fi
printf "\n"
printf "  ${BOLD}Features:${RESET}\n"
[ "$HAS_VULKAN" -eq 1 ] && printf "    ${PASS} Vulkan GPU support\n" || printf "    ${DIM}  Vulkan disabled${RESET}\n"
[ "$HAS_GLFW" -eq 1 ]   && printf "    ${PASS} GLFW windowed mode\n" || printf "    ${DIM}  GLFW disabled${RESET}\n"
[ "$HAS_GLSLC" -eq 1 ]  && printf "    ${PASS} Shader compilation\n" || printf "    ${DIM}  glslc not found${RESET}\n"
printf "\n"
printf "  ${BOLD}Usage:${RESET}\n"
printf "    ${DIM}\$ ${RESET}%s examples/hello.sage\n" "$SAGE_BIN"
printf "    ${DIM}\$ ${RESET}%s                        ${DIM}# REPL${RESET}\n" "$SAGE_BIN"
printf "    ${DIM}\$ ${RESET}%s examples/gpu_planet.sage  ${DIM}# GPU demo${RESET}\n" "$SAGE_BIN"
if [ "$DO_INSTALL" -eq 0 ]; then
    printf "\n  ${DIM}To install: ./build.sh --install${RESET}\n"
fi
printf "\n"
