#!/usr/bin/env bash
# run_parity.sh — Differential parity harness: C interpreter vs self-hosted.
#
# For every testsuite/parity/cases/*.sage this runs three stacks:
#   C   : ./core/sage case.sage                     (reference)
#   SHI : sage self-hosted interpretation
#   SHC : self-hosted --emit-c -> gcc -> native run
#
# Verdicts per case: PARITY (all identical), DIFF-<stack>, FAIL-<stack>,
# SKIP-<stack>. Exit code 0 only when every case reaches PARITY on all
# three stacks.

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"   # repo root
SAGE="$ROOT/core/sage"
SELFHOST_ENTRY="core/src/sage/sage.sage"
CASES_DIR="$ROOT/testsuite/parity/cases"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS_CASES=0; FAIL_CASES=0
declare -a FAILED

norm() { grep -v '^$' | sed 's/[[:space:]]*$//'; }

run_c()    { timeout 60  "$SAGE" "$1" 2>&1 | norm; }
run_shi()  { ( cd "$ROOT" && timeout 300 "$SAGE" "$SELFHOST_ENTRY" "$1" 2>&1 ) | norm; }

run_shc() {
    local case_file="$1" out_c="$WORK/prog.c" out_bin="$WORK/prog"
    if ! (cd "$ROOT" && timeout 300 "$SAGE" "$SELFHOST_ENTRY" \
            --emit-c "$case_file" -o "$out_c" > /dev/null 2>&1) || [ ! -f "$out_c" ]; then
        echo "EMIT_FAIL"; return
    fi
    if ! gcc -O1 -o "$out_bin" "$out_c" -lm 2> /dev/null; then
        echo "GCC_FAIL"; return
    fi
    timeout 30 "$out_bin" 2>&1 | norm
}

verdict() { # verdict <name> <c_out> <shi_out> <shc_out>
    local name="$1" c="$2" shi="$3" shc="$4"
    local status="" ok=1

    if [ "$c" = "TIMEOUT_EXIT" ]; then status="FAIL-C "; ok=0
    elif [ "$shi" = "EMIT_FAIL" ] || [ "$shi" = "GCC_FAIL" ]; then status="BAD"; ok=0; fi

    if [ "$ok" = 1 ]; then
        [ "$c" != "$shi" ] && status="${status}DIFF-SHI "
        case "$shc" in
            EMIT_FAIL|GCC_FAIL) status="${status}SKIP-SHC(${shc%%_FAIL}) " ;;
            *) [ "$c" != "$shc" ] && status="${status}DIFF-SHC " ;;
        esac
        [ -z "$status" ] && status="PARITY"
    fi

    if [ "$status" = "PARITY" ]; then
        PASS_CASES=$((PASS_CASES+1))
        printf '  \033[32m✔ %-34s %s\033[0m\n' "$name" "$status"
    else
        FAIL_CASES=$((FAIL_CASES+1))
        FAILED+=("$name")
        printf '  \033[31m✘ %-34s %s\033[0m\n' "$name" "$status"
        diff <(printf '%s\n' "$c") <(printf '%s\n' "$shi") | head -6 | sed 's/^/      shi | /'
        case "$shc" in EMIT_FAIL|GCC_FAIL) ;; *)
            diff <(printf '%s\n' "$c") <(printf '%s\n' "$shc") | head -6 | sed 's/^/      shc | /'
        esac
    fi
}

echo "── SageLang Compiler Parity ──────────────────────────────"
for case_file in "$CASES_DIR"/*.sage; do
    name=$(basename "$case_file" .sage)
    c_out=$(run_c "$case_file")
    shi_out=$(run_shi "$case_file")
    shc_out=$(run_shc "$case_file")
    verdict "$name" "$c_out" "$shi_out" "$shc_out"
done

echo "───────────────────────────────────────────────────────────"
echo " Parity: $PASS_CASES   Gaps: $FAIL_CASES"
[ "$FAIL_CASES" -eq 0 ]
