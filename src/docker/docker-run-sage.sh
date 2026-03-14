#!/usr/bin/env bash
set -Eeuo pipefail

ARCH="${1:?arch required}"
BIN="${2:-sage}"

case "$ARCH" in
    x86)     PLATFORM="linux/386" ;;
    x86_64)  PLATFORM="linux/amd64" ;;
    arm32)   PLATFORM="linux/arm/v7" ;;
    aarch64) PLATFORM="linux/arm64" ;;
    rv64)    PLATFORM="linux/riscv64" ;;
    *)
        echo "unsupported arch: $ARCH" >&2
        exit 1
        ;;
esac

[[ -f "output/$ARCH/$BIN" ]] || {
    echo "missing binary: output/$ARCH/$BIN" >&2
    exit 1
}

docker run --rm -it \
    --platform "$PLATFORM" \
    -v "$(pwd)/output/$ARCH:/work" \
    -w /work \
    ubuntu:24.04 \
    ./"$BIN"
