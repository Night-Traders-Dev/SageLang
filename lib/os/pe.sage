# PE/COFF (Portable Executable) binary parser
# Parses DOS header, PE signature, COFF header, optional header, and section headers
# Used for Windows executables, DLLs, and UEFI applications

proc read_u16_le(bs, off):
    return bs[off] + bs[off + 1] * 256

proc read_u32_le(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216

proc read_u64_le(bs, off):
    let lo = read_u32_le(bs, off)
    let hi = read_u32_le(bs, off + 4)
    return lo + hi * 4294967296

# DOS header magic: 'MZ' = 0x5A4D
let MZ_MAGIC = 23117

# PE signature: 'PE\0\0' = 0x00004550
let PE_SIGNATURE = 17744

# Machine type constants
let IMAGE_FILE_MACHINE_I386 = 332
let IMAGE_FILE_MACHINE_AMD64 = 34404
let IMAGE_FILE_MACHINE_ARM = 448
let IMAGE_FILE_MACHINE_ARM64 = 43620
let IMAGE_FILE_MACHINE_RISCV64 = 20580
let IMAGE_FILE_MACHINE_EBC = 3772

# Optional header magic
let PE32_MAGIC = 267
let PE32PLUS_MAGIC = 523

# Subsystem constants
let IMAGE_SUBSYSTEM_UNKNOWN = 0
let IMAGE_SUBSYSTEM_NATIVE = 1
let IMAGE_SUBSYSTEM_WINDOWS_GUI = 2
let IMAGE_SUBSYSTEM_WINDOWS_CUI = 3
let IMAGE_SUBSYSTEM_EFI_APPLICATION = 10
let IMAGE_SUBSYSTEM_EFI_BOOT_SERVICE_DRIVER = 11
let IMAGE_SUBSYSTEM_EFI_RUNTIME_DRIVER = 12

# Section characteristic flags
let IMAGE_SCN_CNT_CODE = 32
let IMAGE_SCN_CNT_INITIALIZED_DATA = 64
let IMAGE_SCN_CNT_UNINITIALIZED_DATA = 128
let IMAGE_SCN_MEM_EXECUTE = 536870912
let IMAGE_SCN_MEM_READ = 1073741824
let IMAGE_SCN_MEM_WRITE = 2147483648

proc machine_name(m):
    if m == 332:
        return "i386"
    if m == 34404:
        return "x86_64"
    if m == 448:
        return "ARM"
    if m == 43620:
        return "ARM64"
    if m == 20580:
        return "RISC-V 64"
    if m == 3772:
        return "EFI Byte Code"
    return "Unknown"

proc subsystem_name(s):
    if s == 0:
        return "Unknown"
    if s == 1:
        return "Native"
    if s == 2:
        return "Windows GUI"
    if s == 3:
        return "Windows CUI"
    if s == 10:
        return "EFI Application"
    if s == 11:
        return "EFI Boot Service Driver"
    if s == 12:
        return "EFI Runtime Driver"
    return "Unknown"

# Check for valid MZ header
proc is_pe(bs):
    if len(bs) < 64:
        return false
    return read_u16_le(bs, 0) == 23117

# Parse DOS header (first 64 bytes)
proc parse_dos_header(bs):
    if not is_pe(bs):
        return nil
    let dos = {}
    dos["e_magic"] = read_u16_le(bs, 0)
    dos["e_cblp"] = read_u16_le(bs, 2)
    dos["e_cp"] = read_u16_le(bs, 4)
    dos["e_crlc"] = read_u16_le(bs, 6)
    dos["e_cparhdr"] = read_u16_le(bs, 8)
    dos["e_minalloc"] = read_u16_le(bs, 10)
    dos["e_maxalloc"] = read_u16_le(bs, 12)
    dos["e_ss"] = read_u16_le(bs, 14)
    dos["e_sp"] = read_u16_le(bs, 16)
    dos["e_lfanew"] = read_u32_le(bs, 60)
    return dos

# Parse COFF file header (20 bytes after PE signature)
proc parse_coff_header(bs, pe_off):
    let off = pe_off + 4
    let coff = {}
    coff["machine"] = read_u16_le(bs, off)
    coff["machine_name"] = machine_name(read_u16_le(bs, off))
    coff["num_sections"] = read_u16_le(bs, off + 2)
    coff["timestamp"] = read_u32_le(bs, off + 4)
    coff["symbol_table_offset"] = read_u32_le(bs, off + 8)
    coff["num_symbols"] = read_u32_le(bs, off + 12)
    coff["optional_header_size"] = read_u16_le(bs, off + 16)
    coff["characteristics"] = read_u16_le(bs, off + 18)
    coff["is_executable"] = (read_u16_le(bs, off + 18) & 2) != 0
    coff["is_dll"] = (read_u16_le(bs, off + 18) & 8192) != 0
    return coff

# Parse optional header (variable size, after COFF header)
proc parse_optional_header(bs, pe_off, opt_size):
    if opt_size == 0:
        return nil
    let off = pe_off + 24
    let magic = read_u16_le(bs, off)
    let is_64 = magic == 523
    let opt = {}
    opt["magic"] = magic
    opt["is_pe32plus"] = is_64
    opt["major_linker_version"] = bs[off + 2]
    opt["minor_linker_version"] = bs[off + 3]
    opt["size_of_code"] = read_u32_le(bs, off + 4)
    opt["size_of_initialized_data"] = read_u32_le(bs, off + 8)
    opt["size_of_uninitialized_data"] = read_u32_le(bs, off + 12)
    opt["entry_point"] = read_u32_le(bs, off + 16)
    opt["base_of_code"] = read_u32_le(bs, off + 20)

    if is_64:
        opt["image_base"] = read_u64_le(bs, off + 24)
        opt["section_alignment"] = read_u32_le(bs, off + 32)
        opt["file_alignment"] = read_u32_le(bs, off + 36)
        opt["size_of_image"] = read_u32_le(bs, off + 56)
        opt["size_of_headers"] = read_u32_le(bs, off + 60)
        opt["checksum"] = read_u32_le(bs, off + 64)
        opt["subsystem"] = read_u16_le(bs, off + 68)
        opt["subsystem_name"] = subsystem_name(read_u16_le(bs, off + 68))
        opt["dll_characteristics"] = read_u16_le(bs, off + 70)
        opt["num_data_directories"] = read_u32_le(bs, off + 108)
    else:
        opt["base_of_data"] = read_u32_le(bs, off + 24)
        opt["image_base"] = read_u32_le(bs, off + 28)
        opt["section_alignment"] = read_u32_le(bs, off + 32)
        opt["file_alignment"] = read_u32_le(bs, off + 36)
        opt["size_of_image"] = read_u32_le(bs, off + 56)
        opt["size_of_headers"] = read_u32_le(bs, off + 60)
        opt["checksum"] = read_u32_le(bs, off + 64)
        opt["subsystem"] = read_u16_le(bs, off + 68)
        opt["subsystem_name"] = subsystem_name(read_u16_le(bs, off + 68))
        opt["dll_characteristics"] = read_u16_le(bs, off + 70)
        opt["num_data_directories"] = read_u32_le(bs, off + 92)

    return opt

# Read an 8-byte section name (null-padded ASCII)
proc read_section_name(bs, off):
    let name = ""
    for i in range(8):
        if bs[off + i] == 0:
            return name
        name = name + chr(bs[off + i])
    return name

# Parse a single section header (40 bytes)
proc parse_section(bs, off):
    let sec = {}
    sec["name"] = read_section_name(bs, off)
    sec["virtual_size"] = read_u32_le(bs, off + 8)
    sec["virtual_address"] = read_u32_le(bs, off + 12)
    sec["raw_data_size"] = read_u32_le(bs, off + 16)
    sec["raw_data_offset"] = read_u32_le(bs, off + 20)
    sec["reloc_offset"] = read_u32_le(bs, off + 24)
    sec["linenums_offset"] = read_u32_le(bs, off + 28)
    sec["num_relocs"] = read_u16_le(bs, off + 32)
    sec["num_linenums"] = read_u16_le(bs, off + 34)
    sec["characteristics"] = read_u32_le(bs, off + 36)
    sec["is_code"] = (read_u32_le(bs, off + 36) & 32) != 0
    sec["is_executable"] = (read_u32_le(bs, off + 36) & 536870912) != 0
    sec["is_readable"] = (read_u32_le(bs, off + 36) & 1073741824) != 0
    sec["is_writable"] = (read_u32_le(bs, off + 36) & 2147483648) != 0
    return sec

# Parse all section headers
proc parse_sections(bs, pe_off, coff):
    let sections = []
    let off = pe_off + 24 + coff["optional_header_size"]
    for i in range(coff["num_sections"]):
        push(sections, parse_section(bs, off + i * 40))
    return sections

# High-level: parse entire PE file
proc parse_pe(bs):
    let dos = parse_dos_header(bs)
    if dos == nil:
        return nil
    let pe_off = dos["e_lfanew"]
    # Verify PE signature
    if read_u32_le(bs, pe_off) != 17744:
        return nil
    let pe = {}
    pe["dos"] = dos
    pe["pe_offset"] = pe_off
    pe["coff"] = parse_coff_header(bs, pe_off)
    pe["optional"] = parse_optional_header(bs, pe_off, pe["coff"]["optional_header_size"])
    pe["sections"] = parse_sections(bs, pe_off, pe["coff"])
    return pe

# Find a section by name
proc find_section(pe, name):
    let sections = pe["sections"]
    for i in range(len(sections)):
        if sections[i]["name"] == name:
            return sections[i]
    return nil

# Check if PE is a UEFI application
proc is_uefi_app(pe):
    if pe["optional"] == nil:
        return false
    let sub = pe["optional"]["subsystem"]
    return sub == 10 or sub == 11 or sub == 12

# Read raw bytes from a section
proc section_data(bs, section):
    let data = []
    let off = section["raw_data_offset"]
    let sz = section["raw_data_size"]
    for i in range(sz):
        push(data, bs[off + i])
    return data
