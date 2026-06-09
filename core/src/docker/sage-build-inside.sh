#!/usr/bin/env bash
set -Eeuo pipefail

OUT_DIR="${OUT_DIR:-/out}"

mkdir -p "$OUT_DIR"

cd /src

rm -rf build build_sage

bash build.sh -DBUILD_SAGE=ON

if [[ -f build/sage ]]; then
    cp build/sage "$OUT_DIR/sage_c"
fi

if [[ -f build_sage/sage ]]; then
    cp build_sage/sage "$OUT_DIR/sage_selfhosted"
fi

if [[ -f build/sage-lsp ]]; then
    cp build/sage-lsp "$OUT_DIR/sage_lsp_c"
fi

if [[ -f build_sage/sage-lsp ]]; then
    cp build_sage/sage-lsp "$OUT_DIR/sage_lsp_selfhosted"
fi

file "$OUT_DIR"/* 2>/dev/null || true
ls -l "$OUT_DIR" || true
