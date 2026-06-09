gc_disable()
# EXPECT: 17
# EXPECT: true
# EXPECT: 256
# EXPECT: root

import os.dtb

proc mk_bytes(n):
    let bs = []
    for i in range(n):
        push(bs, 0)
    return bs

proc set_u32_be(bs, off, v):
    bs[off] = (v >> 24) & 255
    bs[off + 1] = (v >> 16) & 255
    bs[off + 2] = (v >> 8) & 255
    bs[off + 3] = v & 255

proc set_u64_be(bs, off, v):
    set_u32_be(bs, off, (v >> 32) & 4294967295)
    set_u32_be(bs, off + 4, v & 4294967295)

# Build a minimal DTB
let bs = mk_bytes(256)

# Header (40 bytes)
# Magic: 0xD00DFEED
set_u32_be(bs, 0, 3490578157)
# Total size
set_u32_be(bs, 4, 256)
# Struct offset
set_u32_be(bs, 8, 56)
# Strings offset
set_u32_be(bs, 12, 200)
# Mem reservation offset
set_u32_be(bs, 16, 40)
# Version
set_u32_be(bs, 20, 17)
# Last compatible version
set_u32_be(bs, 24, 16)
# Boot CPU
set_u32_be(bs, 28, 0)
# String block size
set_u32_be(bs, 32, 10)
# Struct block size
set_u32_be(bs, 36, 100)

# Memory reservation block at offset 40 (terminated by 0,0)
set_u64_be(bs, 40, 0)
set_u64_be(bs, 48, 0)

# Struct block at offset 56
# FDT_BEGIN_NODE (1) + name "root\0" padded to 4
set_u32_be(bs, 56, 1)
bs[60] = 114
bs[61] = 111
bs[62] = 111
bs[63] = 116
bs[64] = 0
# Pad to align4 = 68

# FDT_END_NODE (2)
set_u32_be(bs, 68, 2)

# FDT_END (9)
set_u32_be(bs, 72, 9)

let hdr = dtb.parse_header(bs)
print hdr["version"]
print dtb.is_valid_dtb(bs)
print hdr["totalsize"]

let tree = dtb.parse_tree(bs, hdr)
print tree["name"]
