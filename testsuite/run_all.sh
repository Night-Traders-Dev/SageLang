#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# SageLang — Unified Test Runner
# Runs ALL test suites: unit, compiler, selfhost, benchmarks
# Usage:
#   sh testsuite/run_all.sh                  # everything
#   sh testsuite/run_all.sh unit             # unit tests only
#   sh testsuite/run_all.sh compiler         # C backend compiler tests
#   sh testsuite/run_all.sh selfhost         # self-hosted interpreter tests
#   sh testsuite/run_all.sh benchmarks       # benchmark suite
#   sh testsuite/run_all.sh quick            # unit + compiler (no selfhost)
#   sh testsuite/run_all.sh --filter <name>  # run tests matching pattern
# ═══════════════════════════════════════════════════════════════════════════════

set -uo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SUITE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SUITE_DIR/.." && pwd)"
CORE_DIR="$REPO_ROOT/core"
SAGE="$CORE_DIR/sage"

UNIT_DIR="$SUITE_DIR/unit"
COMPILER_DIR="$SUITE_DIR/compiler"
SELFHOST_DIR="$SUITE_DIR/selfhost"
BENCH_DIR="$SUITE_DIR/benchmarks"

export SAGE_PATH="$CORE_DIR/lib${SAGE_PATH:+:$SAGE_PATH}"

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD='\033[1m'; GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'; DIM='\033[2m'; NC='\033[0m'
ok()   { printf "${GREEN}  ✅ %s${NC}\n" "$*"; }
fail() { printf "${RED}  ❌ %s${NC}\n" "$*"; }
info() { printf "${CYAN}  ▸  %s${NC}\n" "$*"; }
warn() { printf "${YELLOW}  ⚠  %s${NC}\n" "$*"; }
hdr()  { printf "\n${BOLD}${CYAN}══ %s ══${NC}\n\n" "$*"; }

# ── State ─────────────────────────────────────────────────────────────────────
TOTAL_PASS=0; TOTAL_FAIL=0; TOTAL_SKIP=0
FAILED_SUITES=""

add_result() {
    local suite="$1" pass="$2" fail="$3"
    TOTAL_PASS=$((TOTAL_PASS + pass))
    TOTAL_FAIL=$((TOTAL_FAIL + fail))
    [ "$fail" -gt 0 ] && FAILED_SUITES="$FAILED_SUITES $suite" || true
    return 0
}

# ── Build check ───────────────────────────────────────────────────────────────
check_binary() {
    if [ ! -x "$SAGE" ]; then
        warn "sage binary not found at $SAGE"
        printf "  Building...\n"
        if ! (cd "$CORE_DIR" && make -j"$(nproc 2>/dev/null || echo 2)" 2>&1 | tail -5); then
            printf "${RED}Build failed — cannot run tests.${NC}\n"; exit 1
        fi
        [ -x "$SAGE" ] || { printf "${RED}Binary still missing after build.${NC}\n"; exit 1; }
        ok "Built: $SAGE"
    else
        info "Using: $SAGE  ($(du -sh "$SAGE" 2>/dev/null | cut -f1))"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# SUITE: Unit tests  (tests/01..43_*)
# ══════════════════════════════════════════════════════════════════════════════
run_unit() {
    hdr "Unit Tests"
    if [ -f "$UNIT_DIR/run_tests.sh" ]; then
        bash "$UNIT_DIR/run_tests.sh"
        rc=$?
        if [ $rc -eq 0 ]; then add_result "unit" 1 0; else add_result "unit" 0 1; fi
    else
        # Fallback: manually run each numbered suite
        local _p=0 _f=0
        for suite_dir in "$UNIT_DIR"/[0-9][0-9]_*/; do
            [ -d "$suite_dir" ] || continue
            suite_name="$(basename "$suite_dir")"
            local s_pass=0 s_fail=0
            for test_file in "$suite_dir"*.sage; do
                [ -f "$test_file" ] || continue
                expected="${test_file%.sage}.expected"
                if [ -f "$expected" ]; then
                    actual="$(cd "$CORE_DIR" && "$SAGE" "$test_file" 2>&1)"
                    if [ "$actual" = "$(cat "$expected")" ]; then
                        s_pass=$((s_pass+1)); _p=$((++_p))
                    else
                        s_fail=$((s_fail+1)); _f=$((++_f))
                        fail "$suite_name/$(basename "$test_file")"
                    fi
                else
                    if (cd "$CORE_DIR" && "$SAGE" "$test_file" >/dev/null 2>&1); then
                        s_pass=$((s_pass+1)); _p=$((++_p))
                    else
                        s_fail=$((s_fail+1)); _f=$((++_f))
                        fail "$suite_name/$(basename "$test_file")"
                    fi
                fi
            done
            printf "  ${DIM}%-30s${NC}  ${GREEN}%d ok${NC}" "$suite_name" "$s_pass"
            [ $s_fail -gt 0 ] && printf "  ${RED}%d fail${NC}" "$s_fail"
            printf "\n"
        done
        add_result "unit" "$_p" "$_f"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# SUITE: Compiler tests  (testing/)
# ══════════════════════════════════════════════════════════════════════════════
run_compiler() {
    hdr "Compiler Backend Tests"
    local _p=0 _f=0
    TMP="$SUITE_DIR/.tmp"
    mkdir -p "$TMP"

    _run_c_test() {
        local name="$1" sage_file="$2" expected="$3" extra_flags="${4:-}"
        local out_bin="$TMP/c_$name" out_file="$TMP/c_$name.out"
        if (cd "$CORE_DIR" && "$SAGE" --compile "$sage_file" -o "$out_bin" $extra_flags 2>/dev/null) && \
           "$out_bin" > "$out_file" 2>&1 && \
           diff -q "$expected" "$out_file" >/dev/null 2>&1; then
            ok "C backend: $name"; _p=$((_p+1))
        else
            fail "C backend: $name"; _f=$((_f+1))
        fi
    }

    _run_llvm_test() {
        local name="$1" sage_file="$2" expected="$3"
        if ! command -v clang >/dev/null 2>&1; then
            printf "  ${DIM}⏭  LLVM: $name  (clang not found)${NC}\n"
            TOTAL_SKIP=$((TOTAL_SKIP+1)); return
        fi
        local out_bin="$TMP/llvm_$name" out_file="$TMP/llvm_$name.out"
        if (cd "$CORE_DIR" && "$SAGE" --compile-llvm "$sage_file" -o "$out_bin" 2>/dev/null) && \
           "$out_bin" > "$out_file" 2>&1 && \
           diff -q "$expected" "$out_file" >/dev/null 2>&1; then
            ok "LLVM backend: $name"; _p=$((_p+1))
        else
            fail "LLVM backend: $name"; _f=$((_f+1))
        fi
    }

    CD="$COMPILER_DIR"

    # C backend tests
    _run_c_test "smoke"       "$CD/compiler_smoke.sage"       "$CD/compiler_smoke.expected"
    _run_c_test "arrays"      "$CD/compiler_arrays.sage"      "$CD/compiler_arrays.expected"
    _run_c_test "for_loops"   "$CD/compiler_for_loops.sage"   "$CD/compiler_for_loops.expected"
    _run_c_test "dicts"       "$CD/compiler_dicts.sage"       "$CD/compiler_dicts.expected"
    _run_c_test "tuples"      "$CD/compiler_tuples.sage"      "$CD/compiler_tuples.expected"
    _run_c_test "exceptions"  "$CD/compiler_exceptions.sage"  "$CD/compiler_exceptions.expected"
    _run_c_test "strings"     "$CD/compiler_strings.sage"     "$CD/compiler_strings.expected"
    _run_c_test "memory"      "$CD/compiler_memory.sage"      "$CD/compiler_memory.expected"
    _run_c_test "structs"     "$CD/compiler_structs.sage"     "$CD/compiler_structs.expected"
    _run_c_test "classes"     "$CD/compiler_classes.sage"     "$CD/compiler_classes.expected"
    _run_c_test "modules"     "$CD/compiler_modules.sage"     "$CD/compiler_modules.expected"
    _run_c_test "arch"        "$CD/compiler_arch.sage"        "$CD/compiler_arch.expected"
    _run_c_test "constfold"   "$CD/compiler_constfold.sage"   "$CD/compiler_constfold.expected" "-O1"
    _run_c_test "dce"         "$CD/compiler_dce.sage"         "$CD/compiler_dce.expected"       "-O2"
    _run_c_test "inline"      "$CD/compiler_inline.sage"      "$CD/compiler_inline.expected"    "-O3"
    _run_c_test "optlevels"   "$CD/compiler_optlevels.sage"   "$CD/compiler_optlevels.expected"

    # LLVM backend tests
    _run_llvm_test "smoke"    "$CD/compiler_smoke.sage"       "$CD/compiler_smoke.expected"
    _run_llvm_test "features" "$CD/llvm_features.sage"        "$CD/llvm_features.expected"

    # Emit tests (no binary execution, just check output produced)
    if (cd "$CORE_DIR" && "$SAGE" --emit-llvm "$CD/compiler_smoke.sage" -o "$TMP/smoke.ll" 2>/dev/null); then
        ok "LLVM IR emit"; _p=$((_p+1))
    else
        fail "LLVM IR emit"; _f=$((_f+1))
    fi
    if (cd "$CORE_DIR" && "$SAGE" --emit-asm "$CD/compiler_smoke.sage" -o "$TMP/smoke.s" 2>/dev/null); then
        ok "ASM emit"; _p=$((_p+1))
    else
        fail "ASM emit"; _f=$((_f+1))
    fi

    # Interpreter smoke
    if (cd "$CORE_DIR" && "$SAGE" "$CD/test.sage" 2>/dev/null); then
        ok "Interpreter: test.sage"; _p=$((_p+1))
    else
        fail "Interpreter: test.sage"; _f=$((_f+1))
    fi

    # REPL sanity
    if printf ":quit\n" | (cd "$CORE_DIR" && "$SAGE" --repl 2>&1) | grep -q "Sage REPL"; then
        ok "REPL banner"; _p=$((_p+1))
    else
        fail "REPL banner"; _f=$((_f+1))
    fi

    add_result "compiler" "$_p" "$_f"
}

# ══════════════════════════════════════════════════════════════════════════════
# SUITE: Self-hosted tests  (src/sage/test/)
# ══════════════════════════════════════════════════════════════════════════════
run_selfhost() {
    hdr "Self-Hosted Tests  (Sage-in-Sage)"
    local _p=0 _f=0

    SAGE_SRC="$CORE_DIR/src/sage"

    _sh_test() {
        local name="$1" test_file="$SELFHOST_DIR/$2"
        if (cd "$SAGE_SRC" && "$SAGE" "$test_file" 2>&1 | tail -1 | grep -qiE "pass|ok|✓|✅|done"); then
            ok "$name"; _p=$((_p+1))
        else
            fail "$name"; _f=$((_f+1))
        fi
    }

    _sh_test "Lexer"            "test_lexer.sage"
    _sh_test "Parser"           "test_parser.sage"
    _sh_test "Interpreter"      "test_interpreter.sage"
    _sh_test "Bootstrap"        "test_bootstrap.sage"
    _sh_test "Formatter"        "test_formatter.sage"
    _sh_test "Linter"           "test_linter.sage"
    _sh_test "Value"            "test_value.sage"
    _sh_test "Pass"             "test_pass.sage"
    _sh_test "Constfold"        "test_constfold.sage"
    _sh_test "DCE"              "test_dce.sage"
    _sh_test "Inline"           "test_inline.sage"
    _sh_test "Typecheck"        "test_typecheck.sage"
    _sh_test "Stdlib"           "test_stdlib.sage"
    _sh_test "Module"           "test_module.sage"
    _sh_test "LLVM backend"     "test_llvm_backend.sage"
    _sh_test "Codegen"          "test_codegen.sage"
    _sh_test "Compiler"         "test_compiler.sage"
    _sh_test "Errors"           "test_errors.sage"
    _sh_test "LSP"              "test_lsp.sage"
    _sh_test "Sage CLI"         "test_sage_cli.sage"
    _sh_test "Diagnostic"       "test_diagnostic.sage"
    _sh_test "GC"               "test_gc.sage"
    _sh_test "Heartbeat"        "test_heartbeat.sage"
    # GPU tests require Vulkan hardware — skip gracefully if not available
    if vulkaninfo >/dev/null 2>&1 || (command -v vulkaninfo >/dev/null 2>&1); then
        _sh_test "GPU"              "test_gpu.sage"
        _sh_test "GPU advanced"     "test_gpu_advanced.sage"
        _sh_test "GPU features"     "test_gpu_features.sage"
        _sh_test "GPU engine"       "test_gpu_engine.sage"
    else
        printf "  ${DIM}⏭  GPU tests skipped (no Vulkan device)${NC}\n"
        TOTAL_SKIP=$((TOTAL_SKIP + 4))
    fi

    add_result "selfhost" "$_p" "$_f"
}

# ══════════════════════════════════════════════════════════════════════════════
# SUITE: Benchmarks
# ══════════════════════════════════════════════════════════════════════════════
run_benchmarks() {
    hdr "Benchmarks"
    local _p=0 _f=0

    printf "  ${BOLD}Sage vs Python (warmup 1, runs 3):${NC}\n"
    if command -v python3 >/dev/null 2>&1; then
        if python3 "$CORE_DIR/scripts/benchmark_vs_python.py" \
                   --sage "$SAGE" \
                   --tests-dir "$BENCH_DIR" \
                   --runs 3 --warmups 1 2>/dev/null; then
            _p=$((_p+1))
        else
            # Fallback: run individual benchmarks manually
            for bf in "$BENCH_DIR"/0[1-9]_*.sage "$BENCH_DIR"/1[0-9]_*.sage; do
                [ -f "$bf" ] || continue
                name="$(basename "${bf%.sage}")"
                if (cd "$CORE_DIR" && "$SAGE" "$bf" >/dev/null 2>&1); then
                    ok "$name"; _p=$((_p+1))
                else
                    fail "$name"; _f=$((_f+1))
                fi
            done
        fi
    else
        warn "python3 not found — skipping benchmark comparison"
        TOTAL_SKIP=$((TOTAL_SKIP+1))
    fi

    printf "\n  ${BOLD}Native backend benchmark (C vs LLVM):${NC}\n"
    if [ -f "$BENCH_DIR/run_backend_compare.sh" ]; then
        (cd "$CORE_DIR" && bash "$BENCH_DIR/run_backend_compare.sh" 2>/dev/null) && _p=$((_p+1)) || _f=$((_f+1))
    else
        warn "run_backend_compare.sh not found"
        TOTAL_SKIP=$((TOTAL_SKIP+1))
    fi

    add_result "benchmarks" "$_p" "$_f"
}

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
print_summary() {
    printf "\n${BOLD}${CYAN}═══════════════════════════════════════${NC}\n"
    printf "${BOLD}  SageLang Test Results${NC}\n"
    printf "${BOLD}${CYAN}═══════════════════════════════════════${NC}\n\n"
    printf "  ${GREEN}%-8s${NC} %d\n" "Passed:"  "$TOTAL_PASS"
    printf "  ${RED}%-8s${NC} %d\n"   "Failed:"  "$TOTAL_FAIL"
    [ "$TOTAL_SKIP" -gt 0 ] && \
    printf "  ${YELLOW}%-8s${NC} %d\n" "Skipped:" "$TOTAL_SKIP"
    printf "\n"
    if [ "$TOTAL_FAIL" -eq 0 ]; then
        printf "  ${GREEN}${BOLD}✅  All tests passed!${NC}\n\n"
        return 0
    else
        printf "  ${RED}${BOLD}❌  Failed suites:${FAILED_SUITES}${NC}\n\n"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════
MODE="${1:-all}"
FILTER=""
[ "${1:-}" = "--filter" ] && { FILTER="$2"; MODE="all"; }

check_binary

case "$MODE" in
    unit)        run_unit ;;
    compiler)    run_compiler ;;
    selfhost)    run_selfhost ;;
    benchmarks)  run_benchmarks ;;
    quick)       run_unit; run_compiler ;;
    all)
        run_unit
        run_compiler
        run_selfhost
        run_benchmarks
        ;;
    *)
        printf "Unknown mode: %s\n" "$MODE"
        printf "Usage: $0 [all|unit|compiler|selfhost|benchmarks|quick]\n"
        exit 1
        ;;
esac

print_summary
