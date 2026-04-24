#!/bin/bash
set -e

# Configuration
SAGE="./sage"
ARCH="x86_64"
BUILD_DIR="build_os"
BOOT_SRC="lib/os/boot/boot.s"
UEFI_EFI="$BUILD_DIR/bootx64.efi"
DISK_IMG="sageos.img"

mkdir -p $BUILD_DIR

echo "--- Building SageOS UEFI Bootloader (Native PE/COFF) ---"
# Assemble/Compile for Windows COFF target (UEFI compatible)
clang -target x86_64-pc-win32-coff -c $BOOT_SRC -o $BUILD_DIR/boot.obj

# Link using lld-link (Native PE/COFF linker)
# Subsystem for EFI Application
lld-link /subsystem:efi_application /entry:efi_main /out:$UEFI_EFI $BUILD_DIR/boot.obj /base:0x100000 /align:4096

echo "--- Constructing Disk Image ---"
# 1. Create a 64MB empty file
dd if=/dev/zero of=$DISK_IMG bs=1M count=64 2>/dev/null

# 2. Create GPT table and EFI partition using sgdisk
sgdisk -o $DISK_IMG
sgdisk -n 1:2048:4927 -t 1:ef00 -c 1:"EFI System Partition" $DISK_IMG

# 3. Create a temporary FAT12 image for the ESP
ESP_IMG="$BUILD_DIR/esp.img"
dd if=/dev/zero of=$ESP_IMG bs=512 count=2880 2>/dev/null
mkfs.fat -F 12 $ESP_IMG
mmd -i $ESP_IMG ::/EFI
mmd -i $ESP_IMG ::/EFI/BOOT
mcopy -i $ESP_IMG $UEFI_EFI ::/EFI/BOOT/BOOTX64.EFI

# 4. Copy the ESP image into the main image at 1MB offset (LBA 2048)
dd if=$ESP_IMG of=$DISK_IMG bs=512 seek=2048 conv=notrunc 2>/dev/null

echo "✅ Created $DISK_IMG"
echo "--- Build Complete ---"
