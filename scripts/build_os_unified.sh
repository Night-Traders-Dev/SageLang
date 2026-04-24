#!/bin/bash
set -e

# build_os_unified.sh — SageOS Build Script (Unified Kernel)
# Concatenates kernel modules and handles UEFI PE/COFF conversion.

SAGE=./sage
ARCH=x86_64
OUTPUT_DIR=build_os
KERNEL_UNIFIED=$OUTPUT_DIR/kernel_unified.sage
KERNEL_BIN=$OUTPUT_DIR/kernel.elf
UEFI_OBJ=$OUTPUT_DIR/bootx64.o
UEFI_SO=$OUTPUT_DIR/bootx64.so
UEFI_BIN=$OUTPUT_DIR/bootx64.efi
DISK_IMG=sageos.img

mkdir -p $OUTPUT_DIR

echo "--- Preparing Unified Kernel ---"
# Order: dependencies first, shell before kmain
cat lib/os/kernel/pmm.sage \
    lib/os/kernel/vmm.sage \
    lib/os/kernel/console.sage \
    lib/os/kernel/keyboard.sage \
    lib/os/kernel/timer.sage \
    lib/os/kernel/syscall.sage \
    src/user/sh.sage \
    lib/os/kernel/kmain.sage > $KERNEL_UNIFIED

# Strip imports and prefixes
sed -i '/import/d' $KERNEL_UNIFIED
sed -i 's/pmm\.//g' $KERNEL_UNIFIED
sed -i 's/vmm\.//g' $KERNEL_UNIFIED
sed -i 's/console\.//g' $KERNEL_UNIFIED
sed -i 's/keyboard\.//g' $KERNEL_UNIFIED
sed -i 's/timer\.//g' $KERNEL_UNIFIED
sed -i 's/syscall\.//g' $KERNEL_UNIFIED
sed -i 's/sh\.//g' $KERNEL_UNIFIED

echo "--- Building SageOS Kernel (Unified ELF) ---"
$SAGE --compile-bare $KERNEL_UNIFIED -o $KERNEL_BIN --target $ARCH -O2

echo "--- Building SageOS UEFI Bootloader (PE/COFF) ---"
# 1. Compile to object file
$SAGE --compile-uefi lib/os/boot/uefi.sage -o $UEFI_OBJ --target $ARCH -O2

# 2. Link to shared ELF with EFI entry point
cc -shared -nostdlib -Wl,-Bsymbolic -Wl,-T,scripts/efi.lds -o $UEFI_SO $UEFI_OBJ

# 3. Convert ELF to PE/COFF for UEFI
objcopy -j .text -j .sdata -j .data -j .dynamic -j .dynsym -j .rel -j .rela -j .reloc \
        --target=efi-app-x86_64 $UEFI_SO $UEFI_BIN

echo "--- Constructing Disk Image ---"
cat > $OUTPUT_DIR/make_img.sage <<EOF
import os.image.diskimg as diskimg
import io
gc_disable()

# Create a 8MB GPT image
print("Creating GPT image...")
let img = diskimg.create_gpt_image(8)

# Read UEFI binary (Now a valid PE/COFF)
print("Reading UEFI binary...")
let efi_bytes = io.readbytes("$UEFI_BIN")
print("Read " + str(len(efi_bytes)) + " bytes.")

# Add EFI partition and binary
img = diskimg.add_efi_partition(img, efi_bytes)

# Read Kernel binary
print("Reading Kernel binary...")
let kernel_bytes = io.readbytes("$KERNEL_BIN")
print("Read " + str(len(kernel_bytes)) + " bytes.")

# Add Kernel to the same partition (root dir)
print("Adding KERNEL.BIN to partition...")
let info = diskimg.get_efi_partition_info(img)
img = diskimg.write_file(img, info["start"], info["size"], "KERNEL.BIN", kernel_bytes)

# Save image
print("Saving image...")
diskimg.save_image(img, "$DISK_IMG")
print("✅ Created $DISK_IMG")
EOF

$SAGE $OUTPUT_DIR/make_img.sage

echo "--- Build Complete ---"
