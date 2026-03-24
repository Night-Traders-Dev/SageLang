# UEFI data structure parsers
# Parses UEFI System Table, Boot Services, Runtime Services,
# memory maps, and configuration tables from byte arrays

proc read_u16_le(bs, off):
    return bs[off] + bs[off + 1] * 256

proc read_u32_le(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216

proc read_u64_le(bs, off):
    let lo = read_u32_le(bs, off)
    let hi = read_u32_le(bs, off + 4)
    return lo + hi * 4294967296

proc hex_byte(b):
    let hi = (b >> 4) & 15
    let lo = b & 15
    let digits = "0123456789abcdef"
    return digits[hi] + digits[lo]

proc read_guid(bs, off):
    let g = hex_byte(bs[off + 3]) + hex_byte(bs[off + 2]) + hex_byte(bs[off + 1]) + hex_byte(bs[off])
    g = g + "-"
    g = g + hex_byte(bs[off + 5]) + hex_byte(bs[off + 4])
    g = g + "-"
    g = g + hex_byte(bs[off + 7]) + hex_byte(bs[off + 6])
    g = g + "-"
    g = g + hex_byte(bs[off + 8]) + hex_byte(bs[off + 9])
    g = g + "-"
    g = g + hex_byte(bs[off + 10]) + hex_byte(bs[off + 11]) + hex_byte(bs[off + 12])
    g = g + hex_byte(bs[off + 13]) + hex_byte(bs[off + 14]) + hex_byte(bs[off + 15])
    return g

# EFI System Table signature: "IBI SYST" (0x5453595320494249)
let EFI_SYSTEM_TABLE_SIGNATURE_LO = 541936457
let EFI_SYSTEM_TABLE_SIGNATURE_HI = 1414484051

# UEFI memory type constants
let EFI_RESERVED = 0
let EFI_LOADER_CODE = 1
let EFI_LOADER_DATA = 2
let EFI_BOOT_SERVICES_CODE = 3
let EFI_BOOT_SERVICES_DATA = 4
let EFI_RUNTIME_SERVICES_CODE = 5
let EFI_RUNTIME_SERVICES_DATA = 6
let EFI_CONVENTIONAL = 7
let EFI_UNUSABLE = 8
let EFI_ACPI_RECLAIM = 9
let EFI_ACPI_NVS = 10
let EFI_MMIO = 11
let EFI_MMIO_PORT = 12
let EFI_PAL_CODE = 13
let EFI_PERSISTENT = 14

# Memory attribute flags
let EFI_MEMORY_UC = 1
let EFI_MEMORY_WC = 2
let EFI_MEMORY_WT = 4
let EFI_MEMORY_WB = 8
let EFI_MEMORY_UCE = 16
let EFI_MEMORY_WP = 4096
let EFI_MEMORY_RP = 8192
let EFI_MEMORY_XP = 16384
let EFI_MEMORY_NV = 32768
let EFI_MEMORY_RUNTIME = 9223372036854775808

# Well-known UEFI table GUIDs
let EFI_ACPI_20_TABLE_GUID = "8868e871-e4f1-11d3-bc22-0080c73c8881"
let EFI_ACPI_TABLE_GUID = "eb9d2d30-2d88-11d3-9a16-0090273fc14d"
let SMBIOS_TABLE_GUID = "eb9d2d31-2d88-11d3-9a16-0090273fc14d"
let SMBIOS3_TABLE_GUID = "f2fd1544-9794-4a2c-992e-e5bbcf20e394"
let EFI_DT_FIXUP_GUID = "e617d64c-fe08-46da-f4dc-bbd5873e23c"

proc memory_type_name(t):
    if t == 0:
        return "Reserved"
    if t == 1:
        return "LoaderCode"
    if t == 2:
        return "LoaderData"
    if t == 3:
        return "BootServicesCode"
    if t == 4:
        return "BootServicesData"
    if t == 5:
        return "RuntimeServicesCode"
    if t == 6:
        return "RuntimeServicesData"
    if t == 7:
        return "Conventional"
    if t == 8:
        return "Unusable"
    if t == 9:
        return "ACPIReclaim"
    if t == 10:
        return "ACPINVS"
    if t == 11:
        return "MMIO"
    if t == 12:
        return "MMIOPort"
    if t == 13:
        return "PALCode"
    if t == 14:
        return "Persistent"
    return "Unknown"

proc config_table_name(guid):
    if guid == "8868e871-e4f1-11d3-bc22-0080c73c8881":
        return "ACPI 2.0"
    if guid == "eb9d2d30-2d88-11d3-9a16-0090273fc14d":
        return "ACPI 1.0"
    if guid == "eb9d2d31-2d88-11d3-9a16-0090273fc14d":
        return "SMBIOS"
    if guid == "f2fd1544-9794-4a2c-992e-e5bbcf20e394":
        return "SMBIOS 3.0"
    return "Unknown"

# Parse a single EFI memory descriptor (variable size, typically 48 bytes)
proc parse_memory_descriptor(bs, off, desc_size):
    let desc = {}
    desc["type"] = read_u32_le(bs, off)
    desc["type_name"] = memory_type_name(read_u32_le(bs, off))
    desc["physical_start"] = read_u64_le(bs, off + 8)
    desc["virtual_start"] = read_u64_le(bs, off + 16)
    desc["num_pages"] = read_u64_le(bs, off + 24)
    desc["attribute"] = read_u64_le(bs, off + 32)
    desc["size_bytes"] = desc["num_pages"] * 4096
    return desc

# Parse EFI memory map from raw bytes
proc parse_memory_map(bs, desc_size, num_entries):
    let entries = []
    for i in range(num_entries):
        let off = i * desc_size
        if off + 40 > len(bs):
            return entries
        push(entries, parse_memory_descriptor(bs, off, desc_size))
    return entries

# Sum total memory from a parsed memory map
proc total_memory(mem_map):
    let total = 0
    for i in range(len(mem_map)):
        let t = mem_map[i]["type"]
        # Count conventional + loader + boot services memory
        if t == 1 or t == 2 or t == 3 or t == 4 or t == 7:
            total = total + mem_map[i]["size_bytes"]
    return total

# Count usable (conventional) memory pages
proc usable_pages(mem_map):
    let pages = 0
    for i in range(len(mem_map)):
        if mem_map[i]["type"] == 7:
            pages = pages + mem_map[i]["num_pages"]
    return pages

# Find memory regions that will survive ExitBootServices
proc runtime_regions(mem_map):
    let regions = []
    for i in range(len(mem_map)):
        let t = mem_map[i]["type"]
        if t == 5 or t == 6 or t == 9 or t == 10:
            push(regions, mem_map[i])
    return regions

# Parse EFI configuration table entry (GUID + pointer)
proc parse_config_table(bs, off):
    let entry = {}
    entry["guid"] = read_guid(bs, off)
    entry["table_name"] = config_table_name(entry["guid"])
    entry["address"] = read_u64_le(bs, off + 16)
    return entry

# Parse array of configuration table entries
proc parse_config_tables(bs, off, count):
    let tables = []
    for i in range(count):
        let entry_off = off + i * 24
        if entry_off + 24 > len(bs):
            return tables
        push(tables, parse_config_table(bs, entry_off))
    return tables

# Find a configuration table by GUID
proc find_config_table(tables, guid):
    for i in range(len(tables)):
        if tables[i]["guid"] == guid:
            return tables[i]
    return nil

# ACPI RSDP (Root System Description Pointer) parser
# RSDP v1 = 20 bytes, v2 = 36 bytes
proc parse_rsdp(bs, off):
    # Check signature "RSD PTR " (8 bytes)
    let sig = ""
    for i in range(8):
        sig = sig + chr(bs[off + i])
    if sig != "RSD PTR ":
        return nil
    let rsdp = {}
    rsdp["signature"] = sig
    rsdp["checksum"] = bs[off + 8]
    let oem = ""
    for i in range(6):
        if bs[off + 9 + i] != 0:
            oem = oem + chr(bs[off + 9 + i])
    rsdp["oem_id"] = oem
    rsdp["revision"] = bs[off + 15]
    rsdp["rsdt_address"] = read_u32_le(bs, off + 16)
    if bs[off + 15] >= 2:
        rsdp["length"] = read_u32_le(bs, off + 20)
        rsdp["xsdt_address"] = read_u64_le(bs, off + 24)
        rsdp["extended_checksum"] = bs[off + 32]
    return rsdp

# Parse ACPI SDT header (common to RSDT, XSDT, DSDT, etc.)
proc parse_sdt_header(bs, off):
    let hdr = {}
    let sig = ""
    for i in range(4):
        sig = sig + chr(bs[off + i])
    hdr["signature"] = sig
    hdr["length"] = read_u32_le(bs, off + 4)
    hdr["revision"] = bs[off + 8]
    hdr["checksum"] = bs[off + 9]
    let oem = ""
    for i in range(6):
        if bs[off + 10 + i] != 0:
            oem = oem + chr(bs[off + 10 + i])
    hdr["oem_id"] = oem
    let oem_table = ""
    for i in range(8):
        if bs[off + 16 + i] != 0:
            oem_table = oem_table + chr(bs[off + 16 + i])
    hdr["oem_table_id"] = oem_table
    hdr["oem_revision"] = read_u32_le(bs, off + 24)
    hdr["creator_id"] = read_u32_le(bs, off + 28)
    hdr["creator_revision"] = read_u32_le(bs, off + 32)
    return hdr

# Build a minimal EFI memory map for testing
proc make_test_memory_map():
    let entries = []
    let e1 = {}
    e1["type"] = 7
    e1["type_name"] = "Conventional"
    e1["physical_start"] = 1048576
    e1["virtual_start"] = 0
    e1["num_pages"] = 256
    e1["attribute"] = 15
    e1["size_bytes"] = 1048576
    push(entries, e1)
    return entries
