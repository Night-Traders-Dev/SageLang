#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Building SageOS Lenovo 300e image ==="

cd "$HERE"

mkdir -p scripts sageos_build/boot sageos_build/kernel sageos_build/obj sageos_build/logs

# The copied build script expects to run from project root.
bash scripts/build_os_unified.sh

echo
echo "Build complete:"
echo "  sageos.img"
