import os.image.diskimg as diskimg
import io

# Create a 8MB GPT image
let img = diskimg.create_gpt_image(8)

# Read UEFI binary
let efi_bytes = io.readbytes("build_os/bootx64.efi")

# Add EFI partition and binary
img = diskimg.add_efi_partition(img, efi_bytes)

# Read Kernel binary
let kernel_bytes = io.readbytes("build_os/kernel.elf")

# Add Kernel to the same partition (root dir)
img = diskimg.write_file(img, 2048, 32768, "KERNEL.BIN", kernel_bytes)

# Save image
diskimg.save_image(img, "sageos.img")
print("✅ Created sageos.img")
