gc_disable()
# EXPECT: true
# EXPECT: 2
# EXPECT: Linux
# EXPECT: 2048
# EXPECT: 1048576
# EXPECT: FAT32 (LBA)
# EXPECT: true
# EXPECT: 2048
# EXPECT: 536870912

import os.mbr

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

let bs = mk_bytes(512)

# Boot signature
bs[510] = 85
bs[511] = 170

# Partition 1: Linux, starts at LBA 2048, 1M sectors
bs[446] = 128
bs[450] = 131
set_u32(bs, 454, 2048)
set_u32(bs, 458, 1048576)

# Partition 2: FAT32 LBA, starts at LBA 20480, 10M sectors
bs[462] = 0
bs[466] = 12
set_u32(bs, 470, 20480)
set_u32(bs, 474, 10485760)

print mbr.is_valid_mbr(bs)

let m = mbr.parse_mbr(bs)
print m["active_count"]

let p1 = m["partitions"][0]
print p1["type_name"]
print p1["lba_start"]
print p1["sector_count"]

let p2 = m["partitions"][1]
print p2["type_name"]

let boot = mbr.find_bootable(m)
print boot["bootable"]
print boot["lba_start"]
print boot["size_bytes"]
