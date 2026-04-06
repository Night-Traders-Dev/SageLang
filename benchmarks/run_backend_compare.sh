#!/bin/bash
## run_backend_compare.sh — Run backend_compare.sage across all native backends
## Usage: bash benchmarks/run_backend_compare.sh
##
## Tests: AST interpreter, bytecode VM, C-compiled, LLVM-compiled, native asm

set -e

SAGE="./sage"
BENCH="benchmarks/backend_compare.sage"
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

run_backend() {
    local name="$1"
    local cmd="$2"
    local build_cmd="$3"

    printf "  ${CYAN}%-24s${RESET}" "$name"

    # Build phase (if needed)
    if [ -n "$build_cmd" ]; then
        local build_start=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
        if ! eval "$build_cmd" > /dev/null 2>&1; then
            printf "${RED}BUILD FAILED${RESET}\n"
            return
        fi
        local build_end=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
    fi

    # Run phase
    local run_start=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
    local output
    if ! output=$(eval "$cmd" 2>&1); then
        printf "${RED}RUN FAILED${RESET}\n"
        return
    fi
    local run_end=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')

    # Calculate times
    local run_ms=$(( (run_end - run_start) / 1000000 ))

    if [ -n "$build_cmd" ]; then
        local build_ms=$(( (build_end - build_start) / 1000000 ))
        local total_ms=$(( build_ms + run_ms ))
        printf "${GREEN}%6d ms${RESET}  ${DIM}(build: %d ms, run: %d ms)${RESET}\n" "$total_ms" "$build_ms" "$run_ms"
    else
        printf "${GREEN}%6d ms${RESET}  ${DIM}(interpret)${RESET}\n" "$run_ms"
    fi

    # Save output for checksum verification
    echo "$output" > "$TMPDIR/$name.out"
}

# 1. AST Interpreter (default)
run_backend "AST Interpreter" \
    "$SAGE $BENCH"

# 2. Bytecode VM
run_backend "Bytecode VM" \
    "$SAGE --runtime bytecode $BENCH"

# 3. C-compiled binary
run_backend "C Backend" \
    "$TMPDIR/bench_c" \
    "$SAGE --compile $BENCH -o $TMPDIR/bench_c"

# 4. LLVM-compiled binary
if command -v llc >/dev/null 2>&1; then
    run_backend "LLVM Backend" \
        "$TMPDIR/bench_llvm" \
        "$SAGE --compile-llvm $BENCH -o $TMPDIR/bench_llvm"
else
    printf "  ${CYAN}%-24s${RESET}${YELLOW}SKIPPED (no llc)${RESET}\n" "LLVM Backend"
fi

# 5. C-compiled with -O3
run_backend "C Backend -O3" \
    "$TMPDIR/bench_c_o3" \
    "$SAGE --compile $BENCH -o $TMPDIR/bench_c_o3 -O3"

# 6. JIT mode (interpreter with profiling)
run_backend "JIT Profiled" \
    "$SAGE --jit $BENCH"

# 7. AOT compiled binary
run_backend "AOT Backend" \
    "$TMPDIR/bench_aot" \
    "$SAGE --aot $BENCH -o $TMPDIR/bench_aot"

# 8. JIT+AOT (profile-guided AOT)
run_backend "JIT+AOT Backend" \
    "$TMPDIR/bench_jitaot" \
    "$SAGE --aot --jit $BENCH -o $TMPDIR/bench_jitaot"

# 9. Self-hosted interpreter (hybrid JIT/AOT)
run_backend "Self-Hosted Sage" \
    "$SAGE src/sage/sage.sage $BENCH"

# 10. Kotlin transpile (emit only, no JVM run)
printf "  ${CYAN}%-24s${RESET}" "Kotlin Transpile"
kt_start=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
if $SAGE --emit-kotlin "$BENCH" -o "$TMPDIR/bench.kt" > /dev/null 2>&1; then
    kt_end=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
    kt_ms=$(( (kt_end - kt_start) / 1000000 ))
    printf "${GREEN}%6d ms${RESET}  ${DIM}(transpile only)${RESET}\n" "$kt_ms"
else
    printf "${RED}FAILED${RESET}\n"
fi

# Checksum verification
printf "\n  ${DIM}Checksum Verification:${RESET}\n"
BASELINE="$TMPDIR/AST Interpreter.out"
if [ -f "$BASELINE" ]; then
    BASELINE_HASH=$(md5sum "$BASELINE" 2>/dev/null | cut -d' ' -f1 || shasum "$BASELINE" | cut -d' ' -f1)
    for f in "$TMPDIR"/*.out; do
        bname=$(basename "$f" .out)
        HASH=$(md5sum "$f" 2>/dev/null | cut -d' ' -f1 || shasum "$f" | cut -d' ' -f1)
        if [ "$HASH" = "$BASELINE_HASH" ]; then
            printf "    ${GREEN}✓${RESET} %s\n" "$bname"
        else
            printf "    ${RED}✗${RESET} %s ${DIM}(output differs)${RESET}\n" "$bname"
        fi
    done
fi

# Cleanup
rm -rf "$TMPDIR"

printf "\n  ${DIM}Done.${RESET}\n\n"
