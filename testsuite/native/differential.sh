#!/usr/bin/env bash
# Differential test across the three backends, for every program in the corpus.
#
#   1. --emit-c     transpile to C, build with gcc    <- reference
#   2. --emit-asm   the C native emitter, build, run
#   3. codegen.sage the Sage native emitter, build, run
#
# Each native path must agree with the reference where it can be emitted at all.
# A path that declines to emit is not a failure: the C validator rejects native
# calls, and so correctly refuses a while loop, whose lowering needs one. What
# matters is that a path never emits something *different* from the reference.
#
# Native code is emitted for the host target, so this only means anything where
# the host can build and run what it emits. On the OrangePi that is riscv64.
#
# This found two bugs no amount of reading the assembly would have shown: a
# fixed 256-byte frame that any program needing more than 14 virtual registers
# overran, and plain assignment lowering to nil, so a loop body compiled to
# nothing while its control flow looked perfect.
#
# usage: differential.sh [corpus-dir]
set -u

REPO=${REPO:-/home/data/data2/Devel/SageLang}
CORPUS=${1:-"$REPO/testsuite/native/corpus"}
RT="$REPO/testsuite/compiler/asm_runtime.c"
SAGE_BIN="$REPO/core/sage"
SAGE_NATIVE="$REPO/core/src/sage"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

emit_native() {
    # $1 = c|sage, $2 = source, $3 = output basename
    if [ "$1" = c ]; then
        "$SAGE_BIN" --emit-asm "$2" -o "$3.casm"
    else
        ( cd "$SAGE_NATIVE" && ../../sage "$REPO/testsuite/native/emit_rv64.sage" "$2" "$3.sages" )
    fi
}

pass=0
mismatch=0
declined=0

for src in "$CORPUS"/*.sage; do
    [ -e "$src" ] || continue
    base=$(basename "$src" .sage)

    # reference
    if ! "$SAGE_BIN" --emit-c "$src" -o "$W/$base.c" 2>"$W/$base.ce"; then
        printf "  %-22s SKIP  (reference could not emit: %s)\n" "$base" "$(head -1 "$W/$base.ce")"
        continue
    fi
    if ! gcc -O1 -o "$W/$base.ref" "$W/$base.c" -lm 2>"$W/$base.re"; then
        printf "  %-22s SKIP  (reference did not build)\n" "$base"
        continue
    fi
    "$W/$base.ref" > "$W/$base.ref.out" 2>&1

    status=ok
    for which in c sage; do
        if ! emit_native "$which" "$src" "$W/$base" >"$W/$base.$which.e" 2>&1; then
            # Declining is acceptable; emitting something different is not.
            if [ "$which" = c ]; then declined=$((declined+1)); fi
            continue
        fi
        asmf="$W/$base.casm"
        [ "$which" = sage ] && asmf="$W/$base.sages"

        if ! gcc -x assembler -c -o "$W/$base.$which.o" "$asmf" 2>"$W/$base.$which.ge"; then
            echo "  $base: $which native assembly did not assemble"
            head -3 "$W/$base.$which.ge" | sed 's/^/      /'
            status=fail
            continue
        fi
        if ! gcc -static -o "$W/$base.$which.bin" "$W/$base.$which.o" "$RT" -lm 2>"$W/$base.$which.gl"; then
            echo "  $base: $which native did not link"
            head -3 "$W/$base.$which.gl" | sed 's/^/      /'
            status=fail
            continue
        fi
        if ! timeout 20 "$W/$base.$which.bin" > "$W/$base.$which.out" 2>&1; then
            echo "  $base: $which native exited non-zero (crash or hang?)"
            status=fail
            continue
        fi
        if ! diff -q "$W/$base.ref.out" "$W/$base.$which.out" >/dev/null 2>&1; then
            echo "  $base: $which native disagrees with the reference"
            diff -u "$W/$base.ref.out" "$W/$base.$which.out" | head -8 | sed 's/^/      /'
            status=fail
        fi
    done

    if [ "$status" = ok ]; then
        pass=$((pass+1))
    else
        mismatch=$((mismatch+1))
    fi
done

echo ""
echo "Native codegen differential: $pass matching, $mismatch mismatching, $declined declined"
[ "$mismatch" -eq 0 ]
