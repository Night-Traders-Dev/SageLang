# EXPECT: FAT8
# EXPECT: FAT12
# EXPECT: FAT16
# EXPECT: FAT32
# EXPECT: 33
# EXPECT: 2080
# EXPECT: 3

import fat

proc mk_sector():
    let bs = []
    for i in range(512):
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

# FAT8 synthetic tiny volume
let bs8 = mk_sector()
set_u16(bs8, 11, 512)
bs8[13] = 4
set_u16(bs8, 14, 1)
bs8[16] = 1
set_u16(bs8, 17, 16)
set_u16(bs8, 19, 32)
bs8[21] = 248
set_u16(bs8, 22, 1)
let i8 = fat.parse_boot_sector(bs8)
print i8["fat_type"]

# FAT12 (floppy-like)
let bs12 = mk_sector()
set_u16(bs12, 11, 512)
bs12[13] = 1
set_u16(bs12, 14, 1)
bs12[16] = 2
set_u16(bs12, 17, 224)
set_u16(bs12, 19, 2880)
bs12[21] = 240
set_u16(bs12, 22, 9)
let i12 = fat.parse_boot_sector(bs12)
print i12["fat_type"]

# FAT16
let bs16 = mk_sector()
set_u16(bs16, 11, 512)
bs16[13] = 4
set_u16(bs16, 14, 1)
bs16[16] = 2
set_u16(bs16, 17, 512)
set_u16(bs16, 19, 32768)
bs16[21] = 248
set_u16(bs16, 22, 32)
let i16 = fat.parse_boot_sector(bs16)
print i16["fat_type"]

# FAT32
let bs32 = mk_sector()
set_u16(bs32, 11, 512)
bs32[13] = 8
set_u16(bs32, 14, 32)
bs32[16] = 2
set_u16(bs32, 17, 0)
set_u16(bs32, 19, 0)
bs32[21] = 248
set_u16(bs32, 22, 0)
set_u32(bs32, 32, 4194304)
set_u32(bs32, 36, 1024)
set_u32(bs32, 44, 2)
let i32 = fat.parse_boot_sector(bs32)
print i32["fat_type"]

print fat.cluster_to_lba(i12, 2)
print fat.cluster_to_lba(i32, 2)

let off12 = fat.fat_entry_offset(i12, 2)
print off12["byte_offset"]
