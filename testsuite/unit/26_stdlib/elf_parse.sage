gc_disable()
# EXPECT: true
# EXPECT: ELF64
# EXPECT: LSB
# EXPECT: EXEC
# EXPECT: x86_64
# EXPECT: 4194304
# EXPECT: 1
# EXPECT: LOAD
# EXPECT: 5
# EXPECT: .text

import os.elf

# Build a minimal ELF64 LE executable header
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

# ELF header (64 bytes) + 1 phdr (56 bytes) + 2 shdrs (64 bytes each) + shstrtab
let bs = mk_bytes(512)

# ELF magic
bs[0] = 127
bs[1] = 69
bs[2] = 76
bs[3] = 70
bs[4] = 2
bs[5] = 1
bs[6] = 1

# Type: EXEC
set_u16(bs, 16, 2)
# Machine: x86_64
set_u16(bs, 18, 62)
# Version
set_u32(bs, 20, 1)
# Entry point
set_u64(bs, 24, 4194304)
# Program header offset (64)
set_u64(bs, 32, 64)
# Section header offset (120 = 64 + 56)
set_u64(bs, 40, 120)
# ELF header size
set_u16(bs, 52, 64)
# Program header entry size
set_u16(bs, 54, 56)
# Program header count
set_u16(bs, 56, 1)
# Section header entry size
set_u16(bs, 58, 64)
# Section header count
set_u16(bs, 60, 2)
# Section name string table index
set_u16(bs, 62, 1)

# Program header at offset 64: PT_LOAD
set_u32(bs, 64, 1)
set_u32(bs, 68, 5)
set_u64(bs, 72, 0)
set_u64(bs, 80, 4194304)
set_u64(bs, 88, 4194304)
set_u64(bs, 96, 512)
set_u64(bs, 104, 512)
set_u64(bs, 112, 4096)

# Section header 0 at offset 120: SHT_NULL (64 bytes of zeros already)

# Section header 1 at offset 184: .text section (shstrtab)
# name_offset = 1 (first byte of strtab is null, then ".text")
set_u32(bs, 184, 1)
# type = SHT_STRTAB (3)
set_u32(bs, 188, 3)
# offset of string table data = 300
set_u64(bs, 208, 300)
# size = 7 (null + ".text" + null)
set_u64(bs, 216, 7)

# String table at offset 300: \0.text\0
bs[300] = 0
bs[301] = 46
bs[302] = 116
bs[303] = 101
bs[304] = 120
bs[305] = 116
bs[306] = 0

# Tests
print elf.is_elf(bs)

let hdr = elf.parse_header(bs)
print hdr["ident"]["class_name"]
print hdr["ident"]["encoding"]
print hdr["type_name"]
print hdr["machine_name"]
print hdr["entry"]
print hdr["phnum"]

let phdrs = elf.parse_phdrs(bs, hdr)
print phdrs[0]["type_name"]
print phdrs[0]["flags"]

let shdrs = elf.parse_shdrs(bs, hdr)
let name = elf.section_name(bs, hdr, shdrs[1])
print name
