gc_disable()
# EXPECT: true
# EXPECT: 1
# EXPECT: 34
# EXPECT: 128
# EXPECT: EFI System
# EXPECT: 2048
# EXPECT: 1048576

import os.gpt

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

proc set_u64(bs, off, v):
    set_u32(bs, off, v & 4294967295)
    set_u32(bs, off + 4, (v >> 32) & 4294967295)

# Need enough space for GPT header at LBA 1 (offset 512) + partition entries at LBA 2 (offset 1024)
let bs = mk_bytes(4096)

# GPT header at offset 512
# Signature: "EFI PART"
bs[512] = 69
bs[513] = 70
bs[514] = 73
bs[515] = 32
bs[516] = 80
bs[517] = 65
bs[518] = 82
bs[519] = 84

# Revision 1.0
set_u32(bs, 520, 65536)
# Header size
set_u32(bs, 524, 92)
# My LBA
set_u64(bs, 536, 1)
# Alternate LBA
set_u64(bs, 544, 2097151)
# First usable LBA
set_u64(bs, 552, 34)
# Last usable LBA
set_u64(bs, 560, 2097118)
# Partition entry LBA (=2)
set_u64(bs, 584, 2)
# Number of partition entries
set_u32(bs, 592, 128)
# Partition entry size
set_u32(bs, 596, 128)

print gpt.is_valid_gpt(bs, 512)

let hdr = gpt.parse_header(bs, 512)
print hdr["my_lba"]
print hdr["first_usable_lba"]
print hdr["num_partition_entries"]

# Create one EFI System Partition entry at LBA 2 (offset 1024)
# Type GUID: C12A7328-F81F-11D2-BA4B-00A0C93EC93B (EFI System)
# Little-endian encoding of first 3 fields:
# 0xC12A7328 -> bytes: 28 73 2A C1
bs[1024] = 40
bs[1025] = 115
bs[1026] = 42
bs[1027] = 193
# 0xF81F -> bytes: 1F F8
bs[1028] = 31
bs[1029] = 248
# 0x11D2 -> bytes: D2 11
bs[1030] = 210
bs[1031] = 17
# Last 2 fields big-endian: BA4B 00A0C93EC93B
bs[1032] = 186
bs[1033] = 75
bs[1034] = 0
bs[1035] = 160
bs[1036] = 201
bs[1037] = 62
bs[1038] = 201
bs[1039] = 59

# First LBA
set_u64(bs, 1056, 2048)
# Last LBA
set_u64(bs, 1064, 1050623)

let entries = gpt.parse_entries(bs, hdr)
print entries[0]["type_name"]
print entries[0]["first_lba"]
print entries[0]["sector_count"]
