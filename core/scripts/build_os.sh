#!/bin/bash
set -e

# build_os.sh — SageOS Build Script
# Compiles the kernel and bootloader, then constructs a bootable disk image.

SAGE=./sage
ARCH=x86_64
OUTPUT_DIR=build_os
KERNEL_BIN=$OUTPUT_DIR/kernel.elf
UEFI_BIN=$OUTPUT_DIR/bootx64.efi
DISK_IMG=sageos.img

mkdir -p $OUTPUT_DIR

echo "--- Building SageOS Kernel ---"
# Using --compile (C backend) for better compatibility with core libraries
$SAGE --compile lib/os/kernel/kmain.sage -o $KERNEL_BIN --target $ARCH -O2

echo "--- Building SageOS UEFI Bootloader ---"
# We'll use our UEFI generator logic via a Sage script
$SAGE --compile-uefi lib/os/boot/uefi.sage -o $UEFI_BIN --target $ARCH -O2

echo "--- Constructing Disk Image ---"
# Use diskimg.sage to create the image. We'll run it as a script.
# We'll create a small runner script for diskimg.
cat > $OUTPUT_DIR/make_img.sage <<EOF
import os.image.diskimg as diskimg

# Create a 32MB GPT image (reduced from 64MB for build speed)
let img = diskimg.create_gpt_image(32)

# Read UEFI binary
let efi_data = readfile("$UEFI_BIN")
let efi_bytes = []
let i = 0
for i in range(len(efi_data)):
    push(efi_bytes, ord(efi_data[i]))
end

# Add EFI partition and binary
img = diskimg.add_efi_partition(img, efi_bytes)

# Read Kernel binary
let kernel_data = readfile("$KERNEL_BIN")
let kernel_bytes = []
for i in range(len(kernel_data)):
    push(kernel_bytes, ord(kernel_data[i]))
end

# Add Kernel to the same partition (root dir)
img = diskimg.write_file(img, 2048, 32768, "KERNEL.BIN", kernel_bytes)

# Save image
diskimg.save_image(img, "$DISK_IMG")
print("✅ Created $DISK_IMG")
EOF

$SAGE $OUTPUT_DIR/make_img.sage

echo "--- Build Complete ---"
echo "To test in QEMU:"
echo "qemu-system-x86_64 -bios /usr/share/ovmf/OVMF.fd -drive format=raw,file=$DISK_IMG"
