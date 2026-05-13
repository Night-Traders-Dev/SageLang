gc_disable()
# EXPECT: FAT12
# EXPECT: 1
# EXPECT: hello.txt
# EXPECT: false
# EXPECT: 5
# EXPECT: true

import os.fat
import os.fat_dir

# Build a minimal FAT16 disk image in memory
# Layout: boot sector + 1 FAT + root dir + data cluster

proc mk_bytes(n):
    let bs = []
    for i in range(n):
        push(bs, 0)
    return bs

proc set_u16(bs, off, v):
    bs[off] = v & 255
    bs[off + 1] = (v >> 8) & 255

proc set_u32(bs, off, v):
    bs[off] = v & 255
    bs[off + 1] = (v >> 8) & 255
    bs[off + 2] = (v >> 16) & 255
    bs[off + 3] = (v >> 24) & 255

# FAT12 floppy-like: 512 byte sectors, 1 sector/cluster, 1 reserved, 1 FAT, 16 root entries, 2880 total sectors, 9 sectors per FAT
let disk = mk_bytes(4096)

# Boot sector
set_u16(disk, 11, 512)
disk[13] = 1
set_u16(disk, 14, 1)
disk[16] = 1
set_u16(disk, 17, 16)
set_u16(disk, 19, 2880)
disk[21] = 240
set_u16(disk, 22, 9)

let info = fat.parse_boot_sector(disk)
print info["fat_type"]

# FAT table at sector 1 (offset 512)
# FAT12: 3 bytes for 2 entries. Cluster 0,1 reserved; cluster 2 = EOC (0xFFF)
# Entries 0-1: media+0xFFF, Entry 2: 0xFFF (EOC)
disk[512] = 240
disk[513] = 255
disk[514] = 255
# Cluster 2 FAT12: byte_offset = 2 + 1 = 3, so offset 512+3=515
disk[515] = 255
disk[516] = 15

# Root directory starts after reserved(1) + FAT(9) = sector 10, offset 5120
# But disk is only 4096 bytes. Let me use smaller FAT.
# Actually with 1 FAT of 9 sectors: root at sector 10 = offset 5120 > 4096
# Use 1 FAT sector instead: set sectors_per_fat = 1
# Then root at sector 2, offset 1024. First data = sector 2 + (16*32/512)=1 = sector 3, offset 1536

# Fix: use 1 sector per FAT
set_u16(disk, 22, 1)

# Re-parse
let info2 = fat.parse_boot_sector(disk)
# root at sector 2 (reserved=1, fat=1*1=1), offset 1024
# root_dir_sectors = ceil(16*32/512) = 1
# first_data_sector = 1 + 1 + 1 = 3

# Root directory entry at offset 1024
disk[1024] = 72
disk[1025] = 69
disk[1026] = 76
disk[1027] = 76
disk[1028] = 79
disk[1029] = 32
disk[1030] = 32
disk[1031] = 32
disk[1032] = 84
disk[1033] = 88
disk[1034] = 84
disk[1035] = 32
set_u16(disk, 1050, 2)
set_u32(disk, 1052, 5)

# Data cluster 2 at sector 3, offset 1536
disk[1536] = 72
disk[1537] = 101
disk[1538] = 108
disk[1539] = 108
disk[1540] = 111

# Test: list root directory
let entries = fat_dir.list_root(disk, info2)
print len(entries)
print entries[0]["name"]
print entries[0]["is_dir"]
print entries[0]["size"]

# Test: follow chain
let chain = fat_dir.follow_chain(disk, info2, 2)
print len(chain) == 1
