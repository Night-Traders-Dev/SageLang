# EXPECT: true
# EXPECT: x86_64
# EXPECT: 2
# EXPECT: true
# EXPECT: EFI Application
# EXPECT: 4096
# EXPECT: .text
# EXPECT: true
# EXPECT: true

gc_disable()
import os.pe

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

let bs = mk_bytes(512)

# DOS header: MZ magic
bs[0] = 77
bs[1] = 90
# e_lfanew: PE header at offset 128
set_u32(bs, 60, 128)

# PE signature at 128
bs[128] = 80
bs[129] = 69
bs[130] = 0
bs[131] = 0

# COFF header at 132
# Machine: AMD64 (0x8664 = 34404)
set_u16(bs, 132, 34404)
# Number of sections: 2
set_u16(bs, 134, 2)
# Timestamp
set_u32(bs, 136, 1711234567)
# Optional header size: 112 (PE32+ minimum)
set_u16(bs, 148, 112)
# Characteristics: EXECUTABLE_IMAGE (0x0002)
set_u16(bs, 150, 2)

# Optional header at 152
# Magic: PE32+ (0x020B = 523)
set_u16(bs, 152, 523)
# Entry point
set_u32(bs, 168, 4096)
# Image base
set_u64(bs, 176, 4194304)
# Section alignment
set_u32(bs, 184, 4096)
# File alignment
set_u32(bs, 188, 512)
# Size of image
set_u32(bs, 208, 16384)
# Size of headers
set_u32(bs, 212, 512)
# Subsystem: EFI Application (10)
set_u16(bs, 220, 10)

# Section 1 at 264 (152 + 112 = 264): .text
bs[264] = 46
bs[265] = 116
bs[266] = 101
bs[267] = 120
bs[268] = 116
# Virtual size
set_u32(bs, 272, 1024)
# Virtual address
set_u32(bs, 276, 4096)
# Raw data size
set_u32(bs, 280, 512)
# Raw data offset
set_u32(bs, 284, 512)
# Characteristics: CODE | EXECUTE | READ
set_u32(bs, 300, 1610612768)

# Section 2 at 304: .data
bs[304] = 46
bs[305] = 100
bs[306] = 97
bs[307] = 116
bs[308] = 97
set_u32(bs, 312, 512)
set_u32(bs, 316, 8192)
set_u32(bs, 320, 512)
set_u32(bs, 324, 1024)
set_u32(bs, 340, 3221225536)

print pe.is_pe(bs)

let p = pe.parse_pe(bs)
print p["coff"]["machine_name"]
print p["coff"]["num_sections"]
print p["coff"]["is_executable"]
print p["optional"]["subsystem_name"]
print p["optional"]["entry_point"]

print p["sections"][0]["name"]
print p["sections"][0]["is_code"]

print pe.is_uefi_app(p)
