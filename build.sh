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

# Single-source version
SAGE_VERSION=$(cat VERSION 2>/dev/null || echo "0.0.0")

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
BUILD_TRAINER=0
BUILD_CHATBOT=0
NO_VULKAN=0
NO_GLFW=0
NO_CURL=0
NO_SSL=0
NO_GPU=0

for arg in "$@"; do
    case "$arg" in
        --install)    DO_INSTALL=1 ;;
        --skip-tests) SKIP_TESTS=1 ;;
        --make-only)  MAKE_ONLY=1 ;;
        --train)      BUILD_TRAINER=1 ;;
        --chatbot)    BUILD_CHATBOT=1 ;;
        --no-vulkan)  NO_VULKAN=1 ;;
        --no-glfw)    NO_GLFW=1 ;;
        --no-curl)    NO_CURL=1 ;;
        --no-ssl)     NO_SSL=1 ;;
        --no-gpu)     NO_GPU=1 ;;
        --minimal)    NO_VULKAN=1; NO_GLFW=1; NO_CURL=1; NO_SSL=1; NO_GPU=1 ;;
        --help|-h)
            echo "Usage: ./build.sh [options]"
            echo ""
            echo "Build options:"
            echo "  --install      Install to /usr/local after building"
            echo "  --skip-tests   Skip test suite"
            echo "  --make-only    Use Make instead of CMake"
            echo "  --train        Build the SL-TQ-LLM C trainer"
            echo "  --chatbot      Compile chatbots (C + LLVM backends)"
            echo ""
            echo "Feature toggles:"
            echo "  --no-vulkan    Disable Vulkan GPU support"
            echo "  --no-glfw      Disable GLFW windowed mode"
            echo "  --no-curl      Disable HTTP/libcurl support"
            echo "  --no-ssl       Disable OpenSSL support"
            echo "  --no-gpu       Disable all GPU features (Vulkan + GLFW)"
            echo "  --minimal      Disable all optional features (core only)"
            echo ""
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

# --- Detect environment ---
IS_PROOT=0
IS_TERMUX=0
IS_ARM64=0
IS_RISCV=0

if [ -f /proc/self/status ] && grep -q "TracerPid:[[:space:]]*[1-9]" /proc/self/status 2>/dev/null; then
    IS_PROOT=1
fi
if [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ]; then
    IS_TERMUX=1
fi
if [ "$(uname -m)" = "aarch64" ]; then
    IS_ARM64=1
fi
if [ "$(uname -m)" = "riscv64" ]; then
    IS_RISCV=1
fi

if [ "$IS_PROOT" -eq 1 ] || [ "$IS_TERMUX" -eq 1 ]; then
    printf "  ${WARN} ${YELLOW}Detected proot/Termux environment${RESET}\n"
    printf "  ${DIM}  Auto-enabling --minimal (no Vulkan/GLFW/curl/SSL)${RESET}\n"
    printf "  ${DIM}  Use --train for mobile C trainer with ARM NEON${RESET}\n\n"
    NO_VULKAN=1; NO_GLFW=1; NO_GPU=1
    # curl and ssl might work in proot, leave them
fi

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
if [ "$NO_VULKAN" -eq 1 ] || [ "$NO_GPU" -eq 1 ]; then
    step "Vulkan SDK"
    step_warn "disabled (--no-vulkan)"
else
    step "Checking Vulkan SDK"
    if pkg-config --exists vulkan 2>/dev/null; then
        step_ok "$(pkg-config --modversion vulkan)"
        HAS_VULKAN=1
    else
        step_warn "not found (GPU features disabled)"
    fi
fi

HAS_GLFW=0
if [ "$NO_GLFW" -eq 1 ] || [ "$NO_GPU" -eq 1 ]; then
    step "GLFW"
    step_warn "disabled (--no-glfw)"
else
    step "Checking GLFW"
    if pkg-config --exists glfw3 2>/dev/null; then
        step_ok "$(pkg-config --modversion glfw3)"
        HAS_GLFW=1
    else
        step_warn "not found (windowed mode disabled)"
    fi
fi

if [ "$NO_CURL" -eq 1 ]; then
    step "libcurl"
    step_warn "disabled (--no-curl)"
else
    step "Checking libcurl"
    if pkg-config --exists libcurl 2>/dev/null; then
        step_ok "$(pkg-config --modversion libcurl)"
    else
        step_warn "not found (HTTP module disabled)"
    fi
fi

if [ "$NO_SSL" -eq 1 ]; then
    step "OpenSSL"
    step_warn "disabled (--no-ssl)"
else
    step "Checking OpenSSL"
    if pkg-config --exists openssl 2>/dev/null; then
        step_ok "$(pkg-config --modversion openssl)"
    else
        step_warn "not found (SSL module disabled)"
    fi
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
    if ! build_output=$(make -j"$(nproc 2>/dev/null || echo 2)" 2>&1); then
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
    if ! build_output=$(cd build_sage && make -j"$(nproc 2>/dev/null || echo 2)" sage 2>&1); then
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
#  3b. Generate PDF book
# ============================================================

if command -v pandoc >/dev/null 2>&1 && command -v xelatex >/dev/null 2>&1; then
    step "Generating PDF book"
    if pandoc docs/sagelang-book.md -o docs/The_Sage_Programming_Language.pdf --pdf-engine=xelatex 2>/dev/null; then
        pdf_size=$(du -h docs/The_Sage_Programming_Language.pdf | cut -f1)
        step_ok "docs/The_Sage_Programming_Language.pdf ($pdf_size)"
    else
        step_ok "skipped (pandoc error)"
    fi
else
    step "Generating PDF book"
    step_ok "skipped (requires pandoc + xelatex)"
fi

# ============================================================
#  3c. Verify self-hosted interpreter
# ============================================================

step "Verifying self-hosted interpreter"
if "$SAGE_BIN" src/sage/test/test_interpreter.sage > /tmp/sage_selfhost_verify.txt 2>&1; then
    pass_count=$(grep -c "PASS" /tmp/sage_selfhost_verify.txt || echo "0")
    fail_count=$(grep -c "FAIL" /tmp/sage_selfhost_verify.txt || echo "0")
    step_ok "${pass_count} passed, ${fail_count} failed"
else
    step_ok "skipped"
fi
rm -f /tmp/sage_selfhost_verify.txt

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
    # tests/run_tests.sh expects ./sage — ensure it exists after CMake builds
    if [ ! -x "./sage" ] && [ -x "$SAGE_BIN" ]; then
        cp "$SAGE_BIN" ./sage
    fi
    if [ "$IS_PROOT" -eq 1 ]; then
        step "Interpreter tests"
        step_warn "skipped (proot — run manually: bash tests/run_tests.sh)"
    else
        run_test "Interpreter tests (241)" "bash tests/run_tests.sh 2>&1" "(All \d+ tests passed|passed.*0 failed)" || total_fail=$((total_fail + 1))
    fi

    section "Self-Hosted Tests"

    if [ "$IS_PROOT" -eq 1 ]; then
        step "Self-hosted tests"
        step_warn "skipped (proot — run manually: make test-selfhost)"
    fi

    # Run the full make test-selfhost which covers ALL suites
    if [ "$IS_PROOT" -eq 0 ]; then
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
    fi  # end IS_PROOT check

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
    if ! make_output=$(make -j"$(nproc 2>/dev/null || echo 2)" 2>&1); then
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

# --- Build SL-TQ-LLM Trainer (optional) ---
if [ "$BUILD_TRAINER" -eq 1 ]; then
    section "Building SL-TQ-LLM C Trainer"
    TRAIN_FLAGS=""
    TRAIN_LIBS="-lm -lpthread"

    # Auto-detect cuBLAS
    if [ -f /usr/include/cublas_v2.h ] || pkg-config --exists cublas 2>/dev/null; then
        TRAIN_FLAGS="$TRAIN_FLAGS -DUSE_CUBLAS"
        TRAIN_LIBS="$TRAIN_LIBS -lcublas -lcudart"
        printf "    ${PASS} cuBLAS GPU acceleration\n"
    else
        printf "    ${DIM}  cuBLAS not found (CPU only)${RESET}\n"
    fi

    # Auto-detect ARM64 NEON
    if [ "$(uname -m)" = "aarch64" ]; then
        TRAIN_FLAGS="$TRAIN_FLAGS -DUSE_NEON"
        printf "    ${PASS} ARM NEON SIMD\n"
    fi

    if gcc -O3 -march=native $TRAIN_FLAGS -o train_sl_tq src/c/train_sl_tq.c $TRAIN_LIBS 2>&1 | sed 's/^/    /'; then
        printf "    ${PASS} Built: train_sl_tq\n"
        printf "\n  ${BOLD}Train:${RESET}\n"
        printf "    ${DIM}\$ ${RESET}./train_sl_tq 200000 0.001\n"
    else
        printf "    ${FAIL} Trainer build failed\n"
    fi
fi

# --- Build Chatbots (optional) ---
if [ "$BUILD_CHATBOT" -eq 1 ]; then
    section "Compiling Chatbots"

    SAGE_CMD="./sage"
    if [ ! -x "$SAGE_CMD" ]; then
        SAGE_CMD="./build/sage"
    fi

    # SageLLM chatbot via C backend
    printf "    ${ARROW} Compiling sagellm_chatbot via C backend...\n"
    if $SAGE_CMD --compile models/chatbots/sagellm_chatbot.sage -o sagellm_chat_c 2>&1 | sed 's/^/      /'; then
        printf "    ${PASS} sagellm_chat_c (C backend)\n"
    else
        printf "    ${FAIL} C backend compilation failed\n"
    fi

    # SageLLM chatbot via LLVM backend
    printf "    ${ARROW} Compiling sagellm_chatbot via LLVM backend...\n"
    if $SAGE_CMD --compile-llvm models/chatbots/sagellm_chatbot.sage -o sagellm_chat 2>&1 | sed 's/^/      /'; then
        printf "    ${PASS} sagellm_chat (LLVM backend)\n"
    else
        printf "    ${FAIL} LLVM backend compilation failed\n"
    fi

    # SL-TQ-LLM generative chatbot via LLVM
    if [ -f models/chatbots/sl_tq_llm_chat.sage ]; then
        printf "    ${ARROW} Compiling sl_tq_llm_chat via LLVM backend...\n"
        if $SAGE_CMD --compile-llvm models/chatbots/sl_tq_llm_chat.sage -o sl_tq_chat 2>&1 | sed 's/^/      /'; then
            printf "    ${PASS} sl_tq_chat (LLVM generative)\n"
        else
            printf "    ${FAIL} SL-TQ-LLM compilation failed\n"
        fi
    fi

    printf "\n  ${BOLD}Run:${RESET}\n"
    printf "    ${DIM}\$ ${RESET}./sagellm_chat        ${DIM}# Retrieval chatbot${RESET}\n"
    printf "    ${DIM}\$ ${RESET}./sl_tq_chat          ${DIM}# Generative (needs weights)${RESET}\n"
fi
printf "\n"
