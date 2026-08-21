#!/bin/bash
## run_backend_compare.sh — Run backend_compare.sage across ALL SageLang backends
##
## Usage: bash testsuite/benchmarks/run_backend_compare.sh
##
## Coverage matrix (backend → runtime):
##   Interpreters : AST, Bytecode VM (in-process), VM image (.svm), Self-Hosted
##   Compilers    : C (-O0/-O3), LLVM (if llc), AOT, JIT+AOT
##   Profilers    : JIT profiled run
##   Native asm   : x86-64 / aarch64 / rv64 / mips — emit + assemble to object
##                  (hosted native linking is not yet available; see codegen.c)
##   Transpilers  : Kotlin, Android project, Pico-C (emit-only timing)
##   Metal        : SGVM binary build + run attempt (honest FAIL if unsupported)
##
## Every runnable backend's stdout is checksum-verified against the AST baseline.

set -u

SAGE="$(cd "$(dirname "$0")/../../core" && pwd)/sage"
BENCH="$(dirname "$0")/backend_compare.sage"
TMPDIR="/tmp/sage_bench_$$"
mkdir -p "$TMPDIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
DIM='\033[0;90m'
BOLD='\033[1m'
RESET='\033[0m'

printf "\n${BOLD}  SageLang Cross-Backend Benchmark${RESET}\n"
printf "  ${DIM}Workload: %s${RESET}\n" "$BENCH"
printf "  ${DIM}───────────────────────────────────────────────${RESET}\n\n"

# Output files for checksum verification (runnable backends only)
declare -a RUNNABLE_NAMES=()

run_backend() {
    # run_backend <name> <run_cmd> [build_cmd]
    local name="$1"
    local cmd="$2"
    local build_cmd="${3:-}"

    printf "  ${CYAN}%-28s${RESET}" "$name"

    if [ -n "$build_cmd" ]; then
        local build_start=$(date +%s%N)
        if ! eval "$build_cmd" > /dev/null 2>&1; then
            printf "${RED}BUILD FAILED${RESET}\n"
            return 1
        fi
        local build_end=$(date +%s%N)
    fi

    local run_start=$(date +%s%N)
    local output
    if ! output=$(eval "$cmd" 2>&1); then
        printf "${RED}RUN FAILED${RESET}\n"
        return 1
    fi
    local run_end=$(date +%s%N)

    local run_ms=$(( (run_end - run_start) / 1000000 ))
    if [ -n "$build_cmd" ]; then
        local build_ms=$(( (build_end - build_start) / 1000000 ))
        printf "${GREEN}%6d ms${RESET}  ${DIM}(build: %d ms, run: %d ms)${RESET}\n" \
            "$((build_ms + run_ms))" "$build_ms" "$run_ms"
    else
        printf "${GREEN}%6d ms${RESET}  ${DIM}(interpret)${RESET}\n" "$run_ms"
    fi

    echo "$output" > "$TMPDIR/$name.out"
    RUNNABLE_NAMES+=("$name")
    return 0
}

emit_only() {
    # emit_only <name> <emit_cmd> [post_cmd]  — timed generation; optional
    # post step (e.g. assembling) validates toolchain acceptance.
    local name="$1"
    local emit_cmd="$2"
    local post_cmd="${3:-}"

    printf "  ${CYAN}%-28s${RESET}" "$name"
    local t_start=$(date +%s%N)
    if ! eval "$emit_cmd" > /dev/null 2>&1; then
        printf "${RED}EMIT FAILED${RESET}\n"
        return 1
    fi
    if [ -n "$post_cmd" ]; then
        if ! eval "$post_cmd" > /dev/null 2>&1; then
            printf "${RED}ASSEMBLE FAILED${RESET}\n"
            return 1
        fi
    fi
    local t_end=$(date +%s%N)
    printf "${GREEN}%6d ms${RESET}  ${DIM}(emit only)${RESET}\n" $(( (t_end - t_start) / 1000000 ))
    return 0
}

# ── Interpreters ─────────────────────────────────────────────────────────────
run_backend "AST Interpreter" \
    "$SAGE $BENCH"

run_backend "Bytecode VM" \
    "$SAGE --runtime bytecode $BENCH"

run_backend "VM Image (.svm)" \
    "$SAGE --run-vm $TMPDIR/bench.svm" \
    "$SAGE --emit-vm $BENCH -o $TMPDIR/bench.svm"

SELFHOST_ENTRY="$(cd "$(dirname "$0")/../../core/src/sage" && pwd)/sage.sage"
run_backend "Self-Hosted Sage" \
    "$SAGE $SELFHOST_ENTRY $BENCH"

# ── Compiled binaries ────────────────────────────────────────────────────────
run_backend "C Backend" \
    "$TMPDIR/bench_c" \
    "$SAGE --compile $BENCH -o $TMPDIR/bench_c"

run_backend "C Backend -O3" \
    "$TMPDIR/bench_c_o3" \
    "$SAGE --compile $BENCH -o $TMPDIR/bench_c_o3 -O3"

if command -v llc >/dev/null 2>&1; then
    run_backend "LLVM Backend" \
        "$TMPDIR/bench_llvm" \
        "$SAGE --compile-llvm $BENCH -o $TMPDIR/bench_llvm"
else
    printf "  ${CYAN}%-28s${RESET}${YELLOW}SKIPPED (no llc)${RESET}\n" "LLVM Backend"
fi

# ── Profile-guided ───────────────────────────────────────────────────────────
run_backend "JIT Profiled" \
    "$SAGE --jit $BENCH"

run_backend "AOT Backend" \
    "$TMPDIR/bench_aot" \
    "$SAGE --aot $BENCH -o $TMPDIR/bench_aot"

run_backend "JIT+AOT Backend" \
    "$TMPDIR/bench_jitaot" \
    "$SAGE --aot --jit $BENCH -o $TMPDIR/bench_jitaot"

# ── Metal VM ─────────────────────────────────────────────────────────────────
run_backend "SGVM Binary" \
    "$SAGE $TMPDIR/bench.sgvm" \
    "$SAGE --sgvm $BENCH -o $TMPDIR/bench.sgvm" || true

# ── Native assembly (emit + assemble-to-object validation) ───────────────────
# Hosted native executables require a linked sage_rt runtime that is still
# landing in codegen.c; until then we validate that each architecture's
# assembly is emitted and accepted by an assembler.
emit_only "Native x86-64 (asm obj)" \
    "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_x86.s --target x86-64" \
    "cc -c -ffreestanding -fPIC $TMPDIR/bench_x86.s -o $TMPDIR/bench_x86.o"

if command -v aarch64-linux-gnu-as >/dev/null 2>&1; then
    emit_only "Native aarch64 (asm obj)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_a64.s --target aarch64" \
        "aarch64-linux-gnu-as $TMPDIR/bench_a64.s -o $TMPDIR/bench_a64.o"
else
    emit_only "Native aarch64 (emit)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_a64.s --target aarch64" || true
fi

if command -v riscv64-linux-gnu-as >/dev/null 2>&1; then
    emit_only "Native rv64 (asm obj)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_rv.s --target rv64" \
        "riscv64-linux-gnu-as $TMPDIR/bench_rv.s -o $TMPDIR/bench_rv.o"
else
    emit_only "Native rv64 (emit)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_rv.s --target rv64" || true
fi

if command -v mips-linux-gnu-as >/dev/null 2>&1; then
    emit_only "Native mips (asm obj)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_mips.s --target mips" \
        "mips-linux-gnu-as $TMPDIR/bench_mips.s -o $TMPDIR/bench_mips.o"
else
    emit_only "Native mips (emit)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_mips.s --target mips" || true
fi

# Bare-metal freestanding object (x86-64-baremetal profile)
emit_only "Bare-metal x86-64 (obj)" \
    "$SAGE --compile-bare $BENCH -o $TMPDIR/bench_bare.o" || true

# ── Transpilers (emit-only timing) ───────────────────────────────────────────
emit_only "Kotlin Transpile" \
    "$SAGE --emit-kotlin $BENCH -o $TMPDIR/bench.kt" || true

emit_only "Pico-C Emit" \
    "$SAGE --emit-pico-c $BENCH -o $TMPDIR/bench_pico.c" || true

mkdir -p "$TMPDIR/android_out"
emit_only "Android Project Gen" \
    "$SAGE --compile-android $BENCH -o $TMPDIR/android_out" || true

# ── Checksum verification across runnable backends ───────────────────────────
printf "\n  ${DIM}Checksum Verification (vs AST baseline):${RESET}\n"
BASELINE="$TMPDIR/AST Interpreter.out"
if [ -f "$BASELINE" ]; then
    BASELINE_HASH=$(md5sum "$BASELINE" 2>/dev/null | cut -d' ' -f1)
    for name in "${RUNNABLE_NAMES[@]}"; do
        f="$TMPDIR/$name.out"
        [ -f "$f" ] || continue
        HASH=$(md5sum "$f" 2>/dev/null | cut -d' ' -f1)
        if [ "$HASH" = "$BASELINE_HASH" ]; then
            printf "    ${GREEN}✓${RESET} %s\n" "$name"
        else
            printf "    ${RED}✗${RESET} %s ${DIM}(output differs)${RESET}\n" "$name"
        fi
    done
fi

# Cleanup
rm -rf "$TMPDIR"
