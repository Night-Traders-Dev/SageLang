gc_disable()
# EXPECT: image_created
# EXPECT: mbr_written
# EXPECT: partition_added
# EXPECT: PASS

import os.image.diskimg

# Create a small 1 MB disk image
let img = diskimg.create_image(1)
if len(img) == 1048576
    print "image_created"
end

# Write an MBR with empty bootloader
let boot = []
let i = 0
while i < 446
    push(boot, 0)
    i = i + 1
end
img = diskimg.write_mbr(img, boot)

# Check MBR signature at bytes 510-511
if img[510] == 0x55
    if img[511] == 0xAA
        print "mbr_written"
    end
end

# Add a FAT16 partition
let start_lba = 2048
let total_sectors = 1048576 / 512
let part_size = total_sectors - start_lba
img = diskimg.create_partition(img, start_lba, part_size, diskimg.PARTITION_FAT16, true)

# Verify partition entry was written (byte at offset 446+4 should be type)
if img[450] == diskimg.PARTITION_FAT16
    print "partition_added"
end

print "PASS"
