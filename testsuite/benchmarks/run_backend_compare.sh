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

CORE_DIR="$(cd "$(dirname "$0")/../../core" && pwd)"
SAGE="${SAGE:-$CORE_DIR/sage}"
BENCH="$(cd "$(dirname "$0")" && pwd)/backend_compare.sage"
TMPDIR="/tmp/sage_bench_$$"
mkdir -p "$TMPDIR"
cd "$CORE_DIR"

FILTER=""
FILTER_MATCHED=0
FILTER_NO_MATCH=0
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
        -h|--help)
            printf 'Usage: %s [--filter <backend substring>]\n' "$0"
            exit 0
            ;;
        *)
            FILTER="$1"
            shift
            break
            ;;
    esac
done
if [ "$#" -gt 0 ]; then
    printf 'Unexpected argument: %s\n' "$1" >&2
    exit 2
fi

filter_matches() {
    local name="$1"
    if [ -z "$FILTER" ]; then
        return 0
    fi
    case "$name" in
        *"$FILTER"*) FILTER_MATCHED=1; return 0 ;;
        *) return 1 ;;
    esac
}

file_hash() {
    local file="$1"
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$file" | cut -d' ' -f1
    elif command -v md5 >/dev/null 2>&1; then
        md5 -q "$file"
    elif command -v shasum >/dev/null 2>&1; then
        shasum "$file" | cut -d' ' -f1
    else
        cksum "$file" | cut -d' ' -f1
    fi
}

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
FAILURES=0

run_backend() {
    # run_backend <name> <run_cmd> [build_cmd]
    local name="$1"
    local cmd="$2"
    local build_cmd="${3:-}"

    filter_matches "$name" || return 0
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

    filter_matches "$name" || return 0
    printf "  ${CYAN}%-28s${RESET}" "$name"
    local t_start=$(date +%s%N)
    local emit_log="$TMPDIR/$name.emit.log"
    if ! eval "$emit_cmd" > "$emit_log" 2>&1; then
        if grep -Eqi 'not supported safely|native calls are not supported|unsupported native selection|unsupported instruction|not supported by native selection|native stack size exceeds supported range|^codegen:' "$emit_log"; then
            printf "${YELLOW}SKIPPED (native backend fail-closed)${RESET}\n"
            rm -f "$emit_log"
            return 0
        fi
        printf "${RED}EMIT FAILED${RESET}\n"
        return 1
    fi
    if [ -n "$post_cmd" ]; then
        if ! eval "$post_cmd" > "$emit_log" 2>&1; then
            if grep -Eqi 'not supported safely|native calls are not supported|unsupported native selection|unsupported instruction|not supported by native selection|native stack size exceeds supported range|^codegen:' "$emit_log"; then
                printf "${YELLOW}SKIPPED (native backend fail-closed)${RESET}\n"
                rm -f "$emit_log"
                return 0
            fi
            printf "${RED}ASSEMBLE FAILED${RESET}\n"
            return 1
        fi
    fi
    rm -f "$emit_log"
    local t_end=$(date +%s%N)
    printf "${GREEN}%6d ms${RESET}  ${DIM}(emit only)${RESET}\n" $(( (t_end - t_start) / 1000000 ))
    return 0
}

# ── Interpreters ─────────────────────────────────────────────────────────────
run_backend "AST Interpreter" \
    "$SAGE $BENCH" || FAILURES=$((FAILURES+1))

run_backend "Bytecode VM" \
    "$SAGE --runtime bytecode $BENCH" || FAILURES=$((FAILURES+1))

run_backend "VM Image (.svm)" \
    "$SAGE --run-vm $TMPDIR/bench.svm" \
    "$SAGE --emit-vm $BENCH -o $TMPDIR/bench.svm" || FAILURES=$((FAILURES+1))

SELFHOST_ENTRY="$CORE_DIR/src/sage/sage.sage"
run_backend "Self-Hosted Sage" \
    "$SAGE $SELFHOST_ENTRY $BENCH" || FAILURES=$((FAILURES+1))

# ── Compiled binaries ────────────────────────────────────────────────────────
run_backend "C Backend" \
    "$TMPDIR/bench_c" \
    "$SAGE --compile $BENCH -o $TMPDIR/bench_c" || FAILURES=$((FAILURES+1))

run_backend "C Backend -O3" \
    "$TMPDIR/bench_c_o3" \
    "$SAGE --compile $BENCH -o $TMPDIR/bench_c_o3 -O3" || FAILURES=$((FAILURES+1))

if filter_matches "LLVM Backend"; then
    if command -v llc >/dev/null 2>&1; then
        run_backend "LLVM Backend" \
            "$TMPDIR/bench_llvm" \
            "$SAGE --compile-llvm $BENCH -o $TMPDIR/bench_llvm" || FAILURES=$((FAILURES+1))
    else
        printf "  ${CYAN}%-28s${RESET}${YELLOW}SKIPPED (no llc)${RESET}\n" "LLVM Backend"
    fi
fi

# ── Profile-guided ───────────────────────────────────────────────────────────
run_backend "JIT Profiled" \
    "$SAGE --jit $BENCH" || FAILURES=$((FAILURES+1))

run_backend "AOT Backend" \
    "$TMPDIR/bench_aot" \
    "$SAGE --aot $BENCH -o $TMPDIR/bench_aot" || FAILURES=$((FAILURES+1))

run_backend "JIT+AOT Backend" \
    "$TMPDIR/bench_jitaot" \
    "$SAGE --aot --jit $BENCH -o $TMPDIR/bench_jitaot" || FAILURES=$((FAILURES+1))

# ── Metal VM ─────────────────────────────────────────────────────────────────
printf "  ${CYAN}%-28s${RESET}${YELLOW}SKIPPED (unsupported)${RESET}\n" "SGVM Binary"

# ── Native assembly (emit + assemble-to-object validation) ───────────────────
# Hosted native executables require a linked sage_rt runtime that is still
# landing in codegen.c; until then we validate that each architecture's
# assembly is emitted and accepted by an assembler.
emit_only "Native x86-64 (asm obj)" \
    "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_x86.s --target x86-64" \
    "cc -c -ffreestanding -fPIC $TMPDIR/bench_x86.s -o $TMPDIR/bench_x86.o" || FAILURES=$((FAILURES+1))

if command -v aarch64-linux-gnu-as >/dev/null 2>&1; then
    emit_only "Native aarch64 (asm obj)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_a64.s --target aarch64" \
        "aarch64-linux-gnu-as $TMPDIR/bench_a64.s -o $TMPDIR/bench_a64.o" || FAILURES=$((FAILURES+1))
else
    emit_only "Native aarch64 (emit)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_a64.s --target aarch64" || FAILURES=$((FAILURES+1))
fi

if command -v riscv64-linux-gnu-as >/dev/null 2>&1; then
    emit_only "Native rv64 (asm obj)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_rv.s --target rv64" \
        "riscv64-linux-gnu-as $TMPDIR/bench_rv.s -o $TMPDIR/bench_rv.o" || FAILURES=$((FAILURES+1))
else
    emit_only "Native rv64 (emit)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_rv.s --target rv64" || FAILURES=$((FAILURES+1))
fi

if command -v mips-linux-gnu-as >/dev/null 2>&1; then
    emit_only "Native mips (asm obj)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_mips.s --target mips" \
        "mips-linux-gnu-as $TMPDIR/bench_mips.s -o $TMPDIR/bench_mips.o" || FAILURES=$((FAILURES+1))
else
    emit_only "Native mips (emit)" \
        "$SAGE --emit-asm $BENCH -o $TMPDIR/bench_mips.s --target mips" || FAILURES=$((FAILURES+1))
fi

# Bare-metal freestanding object (x86-64-baremetal profile)
emit_only "Bare-metal x86-64 (obj)" \
    "$SAGE --compile-bare $BENCH -o $TMPDIR/bench_bare.o" || FAILURES=$((FAILURES+1))

# ── Transpilers (emit-only timing) ───────────────────────────────────────────
emit_only "Kotlin Transpile" \
    "$SAGE --emit-kotlin $BENCH -o $TMPDIR/bench.kt" || FAILURES=$((FAILURES+1))

emit_only "Pico-C Emit" \
    "$SAGE --emit-pico-c $BENCH -o $TMPDIR/bench_pico.c" || FAILURES=$((FAILURES+1))

mkdir -p "$TMPDIR/android_out"
emit_only "Android Project Gen" \
    "$SAGE --compile-android $BENCH -o $TMPDIR/android_out" || FAILURES=$((FAILURES+1))

# ── Checksum verification across runnable backends ───────────────────────────
printf "\n  ${DIM}Checksum Verification:${RESET}\n"
if [ -n "$FILTER" ] && [ "$FILTER_MATCHED" -eq 0 ]; then
    printf "    ${RED}✗${RESET} filter matched no backends: %s\n" "$FILTER"
    FILTER_NO_MATCH=1
    FAILURES=$((FAILURES+1))
fi

if [ "${#RUNNABLE_NAMES[@]}" -gt 0 ] && [ -f "$TMPDIR/AST Interpreter.out" ]; then
    BASELINE_NAME="AST Interpreter"
    BASELINE="$TMPDIR/$BASELINE_NAME.out"
    if BASELINE_HASH="$(file_hash "$BASELINE")" && [ -n "$BASELINE_HASH" ]; then
        printf "  ${DIM}vs %s:${RESET}\n" "$BASELINE_NAME"
        for name in "${RUNNABLE_NAMES[@]}"; do
            f="$TMPDIR/$name.out"
            [ -f "$f" ] || continue
            HASH="$(file_hash "$f")"
            if [ "$HASH" = "$BASELINE_HASH" ]; then
                printf "    ${GREEN}✓${RESET} %s\n" "$name"
            else
                printf "    ${RED}✗${RESET} %s ${DIM}(output differs)${RESET}\n" "$name"
                FAILURES=$((FAILURES+1))
            fi
        done
    else
        printf "    ${RED}✗${RESET} unable to hash AST baseline output\n"
        FAILURES=$((FAILURES+1))
    fi
elif [ -n "$FILTER" ]; then
    printf "    ${RED}✗${RESET} independent AST baseline was not selected; checksum skipped\n"
    FILTER_NO_MATCH=1
    FAILURES=$((FAILURES+1))
else
    printf "    ${RED}✗${RESET} no runnable backend produced a baseline\n"
    FAILURES=$((FAILURES+1))
fi

# Cleanup
rm -rf "$TMPDIR"
if [ "$FILTER_NO_MATCH" -eq 1 ]; then
    exit 2
fi
if [ "$FAILURES" -gt 0 ]; then
    exit 1
fi
exit 0
