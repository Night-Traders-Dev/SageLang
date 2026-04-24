#!/usr/bin/env bash
set -euo pipefail

pkill -9 -f qemu-system-x86_64 >/dev/null 2>&1 || true

qemu-system-x86_64 \
  -bios /usr/share/ovmf/OVMF.fd \
  -drive file=sageos.img,format=raw,snapshot=on \
  -m 256M \
  -serial stdio
