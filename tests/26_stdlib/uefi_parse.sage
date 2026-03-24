gc_disable()
# EXPECT: Conventional
# EXPECT: 256
# EXPECT: 1048576
# EXPECT: 1048576
# EXPECT: 8
# EXPECT: 2
# EXPECT: ACPI 2.0
# EXPECT: APIC
# EXPECT: 2
# EXPECT: 1

import os.uefi
import os.acpi

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

# Test memory map parsing
let mem_bs = mk_bytes(96)

# Entry 0: Conventional memory
set_u32(mem_bs, 0, 7)
set_u64(mem_bs, 8, 1048576)
set_u64(mem_bs, 16, 0)
set_u64(mem_bs, 24, 256)
set_u64(mem_bs, 32, 15)

# Entry 1: Runtime Services Data
set_u32(mem_bs, 48, 6)
set_u64(mem_bs, 56, 4293918720)
set_u64(mem_bs, 64, 0)
set_u64(mem_bs, 72, 16)
set_u64(mem_bs, 80, 15)

let mmap = uefi.parse_memory_map(mem_bs, 48, 2)
print mmap[0]["type_name"]
print mmap[0]["num_pages"]
print mmap[0]["size_bytes"]

let total = uefi.total_memory(mmap)
print total

# Test RSDP parsing
let rsdp_bs = mk_bytes(36)
# "RSD PTR "
rsdp_bs[0] = 82
rsdp_bs[1] = 83
rsdp_bs[2] = 68
rsdp_bs[3] = 32
rsdp_bs[4] = 80
rsdp_bs[5] = 84
rsdp_bs[6] = 82
rsdp_bs[7] = 32
# Revision 2
rsdp_bs[15] = 2
# RSDT address
set_u32(rsdp_bs, 16, 4026531840)
# Length
set_u32(rsdp_bs, 20, 36)
# XSDT address
set_u64(rsdp_bs, 24, 4026531840)

let rsdp = uefi.parse_rsdp(rsdp_bs, 0)
print len(rsdp["signature"])
print rsdp["revision"]

# Test config table parsing
let ct_bs = mk_bytes(48)
# ACPI 2.0 GUID: 8868e871-e4f1-11d3-bc22-0080c73c8881
ct_bs[0] = 113
ct_bs[1] = 232
ct_bs[2] = 104
ct_bs[3] = 136
ct_bs[4] = 241
ct_bs[5] = 228
ct_bs[6] = 211
ct_bs[7] = 17
ct_bs[8] = 188
ct_bs[9] = 34
ct_bs[10] = 0
ct_bs[11] = 128
ct_bs[12] = 199
ct_bs[13] = 60
ct_bs[14] = 136
ct_bs[15] = 129
set_u64(ct_bs, 16, 4026531840)

let tables = uefi.parse_config_tables(ct_bs, 0, 1)
print tables[0]["table_name"]

# Test ACPI MADT parsing
let madt_bs = mk_bytes(64)
# Signature: "APIC"
madt_bs[0] = 65
madt_bs[1] = 80
madt_bs[2] = 73
madt_bs[3] = 67
# Length: 60
set_u32(madt_bs, 4, 60)
# Local APIC address
set_u32(madt_bs, 36, 4261412864)
# Flags: has 8259
set_u32(madt_bs, 40, 1)

# MADT entry: Local APIC (type 0, len 8)
madt_bs[44] = 0
madt_bs[45] = 8
madt_bs[46] = 0
madt_bs[47] = 0
# Flags: enabled
set_u32(madt_bs, 48, 1)

# MADT entry: I/O APIC (type 1, len 12)
madt_bs[52] = 1
madt_bs[53] = 8
madt_bs[54] = 0
set_u32(madt_bs, 56, 4261478400)

let madt = acpi.parse_madt(madt_bs, 0)
print madt["header"]["signature"]
print len(madt["entries"])

let cpu_count = acpi.count_processors(madt)
print cpu_count
