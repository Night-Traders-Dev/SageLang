#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/sageos_build"
BOOT="$BUILD/boot"
OBJ="$BUILD/obj"
IMG="$ROOT/sageos.img"
ESP="$BUILD/esp.img"

IMG_SIZE_MIB=96
ESP_SIZE_MIB=64
ESP_START_LBA=2048

mkdir -p "$BUILD" "$OBJ" "$BUILD/logs"

echo "--- Cleaning stale objects/images ---"
rm -f "$BUILD/kernel.o" "$BUILD/runtime.o"
rm -f "$ROOT/build_os/kernel.o" "$ROOT/build_os/runtime.o" 2>/dev/null || true
rm -f "$BUILD/BOOTX64.EFI" "$BUILD/uefi_loader.obj"
rm -f "$BUILD/kernel.elf" "$BUILD/KERNEL.BIN"
rm -f "$ESP" "$IMG"

echo "--- Building UEFI loader (MS ABI PE/COFF + GOP handoff) ---"
clang \
  -target x86_64-windows-msvc \
  -ffreestanding \
  -fno-stack-protector \
  -fshort-wchar \
  -mno-red-zone \
  -Wall \
  -Wextra \
  -c "$BOOT/uefi_loader.c" \
  -o "$OBJ/uefi_loader.obj"

lld-link \
  /subsystem:efi_application \
  /entry:EfiMain \
  /nodefaultlib \
  /out:"$BUILD/BOOTX64.EFI" \
  "$OBJ/uefi_loader.obj"

echo "--- Building SageOS Kernel ---"
"$BUILD/build_kernel.sh"

echo "--- Creating ESP FAT image ---"
dd if=/dev/zero of="$ESP" bs=1M count="$ESP_SIZE_MIB" status=none
mkfs.fat -F 32 -n SAGEOS "$ESP" >/dev/null

mmd -i "$ESP" ::/EFI
mmd -i "$ESP" ::/EFI/BOOT
mcopy -i "$ESP" "$BUILD/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$ESP" "$BUILD/KERNEL.BIN" ::/KERNEL.BIN

echo "--- Creating GPT disk image ---"
truncate -s "${IMG_SIZE_MIB}M" "$IMG"

sgdisk --clear "$IMG" >/dev/null
sgdisk \
  --new=1:${ESP_START_LBA}:+${ESP_SIZE_MIB}M \
  --typecode=1:EF00 \
  --change-name=1:"EFI System" \
  "$IMG" >/dev/null

dd if="$ESP" of="$IMG" bs=512 seek="$ESP_START_LBA" conv=notrunc status=none

echo "--- Verifying GPT ---"
sgdisk -v "$IMG"

echo "--- Verifying EFI image signature ---"
file "$BUILD/BOOTX64.EFI" || true

echo "--- Build complete ---"
echo "Image:  $IMG"
echo "UEFI:   $BUILD/BOOTX64.EFI"
echo "Kernel: $BUILD/KERNEL.BIN"
