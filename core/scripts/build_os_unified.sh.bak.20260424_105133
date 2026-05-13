#!/bin/bash
set -e

# Configuration
SAGE="sage"
ARCH="x86_64"
BUILD_DIR="sageos_build"
BOOT_SRC="lib/os/boot/boot.s"
KERNEL_SRC="lib/os/kernel/kmain.sage"
UEFI_EFI="$BUILD_DIR/BOOTX64.EFI"
DISK_IMG="sageos.img"

mkdir -p $BUILD_DIR

echo "--- Building SageOS Kernel ---"
./sageos_build/build_kernel.sh

echo "--- Building SageOS UEFI Bootloader (Native PE/COFF) ---"
# Assemble/Compile for Windows COFF target (UEFI compatible)
clang -target x86_64-pc-windows-msvc -c lib/os/boot/boot.s -o $BUILD_DIR/boot.o
clang -target x86_64-pc-windows-msvc -ffreestanding -fno-stack-protector -fshort-wchar -mno-red-zone -c lib/os/boot/boot_main.c -o $BUILD_DIR/boot_main.o
# Link as EFI application
lld-link /subsystem:efi_application /entry:efi_main /out:$BUILD_DIR/BOOTX64.EFI $BUILD_DIR/boot.o $BUILD_DIR/boot_main.o

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
mcopy -i $ESP_IMG $BUILD_DIR/kernel.bin ::/KERNEL.BIN

# 4. Copy the ESP image into the main image at 1MB offset (LBA 2048)
dd if=$ESP_IMG of=$DISK_IMG bs=512 seek=2048 conv=notrunc 2>/dev/null

echo "✅ Created $DISK_IMG"
echo "--- Build Complete ---"
