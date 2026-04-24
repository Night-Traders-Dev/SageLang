import os.image.diskimg as diskimg
import io
gc_disable()

# Create a 8MB GPT image
print("Creating GPT image...")
let img = diskimg.create_gpt_image(8)

# Read UEFI binary (Now a valid PE/COFF)
print("Reading UEFI binary...")
let efi_bytes = io.readbytes("build_os/bootx64.efi")
print("Read " + str(len(efi_bytes)) + " bytes.")

# Add EFI partition and binary
img = diskimg.add_efi_partition(img, efi_bytes)

# Read Kernel binary
print("Reading Kernel binary...")
let kernel_bytes = io.readbytes("build_os/kernel.elf")
print("Read " + str(len(kernel_bytes)) + " bytes.")

# Add Kernel to the same partition (root dir)
print("Adding KERNEL.BIN to partition...")
let info = diskimg.get_efi_partition_info(img)
img = diskimg.write_file(img, info["start"], info["size"], "KERNEL.BIN", kernel_bytes)

# Save image
print("Saving image...")
diskimg.save_image(img, "sageos.img")
print("✅ Created sageos.img")
