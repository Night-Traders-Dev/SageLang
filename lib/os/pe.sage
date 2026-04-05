gc_disable()
# PE/COFF (Portable Executable) binary parser
# Parses DOS header, PE signature, COFF header, optional header, and section headers
# Used for Windows executables, DLLs, and UEFI applications

@inline
proc read_u16_le(bs, off):
    return bs[off] + bs[off + 1] * 256
end

@inline
proc read_u32_le(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216
end

proc read_u64_le(bs, off):
    let lo = read_u32_le(bs, off)
    let hi = read_u32_le(bs, off + 4)
    return lo + hi * 4294967296
end

comptime:
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
end

proc machine_name(m):
    if m == 332:
        return "i386"
    end
    if m == 34404:
        return "x86_64"
    end
    if m == 448:
        return "ARM"
    end
    if m == 43620:
        return "ARM64"
    end
    if m == 20580:
        return "RISC-V 64"
    end
    if m == 3772:
        return "EFI Byte Code"
    end
    return "Unknown"
end

proc subsystem_name(s):
    if s == 0:
        return "Unknown"
    end
    if s == 1:
        return "Native"
    end
    if s == 2:
        return "Windows GUI"
    end
    if s == 3:
        return "Windows CUI"
    end
    if s == 10:
        return "EFI Application"
    end
    if s == 11:
        return "EFI Boot Service Driver"
    end
    if s == 12:
        return "EFI Runtime Driver"
    end
    return "Unknown"
end

# Check for valid MZ header
@inline
proc is_pe(bs):
    if len(bs) < 64:
        return false
    end
    return read_u16_le(bs, 0) == 23117
end

# Parse DOS header (first 64 bytes)
proc parse_dos_header(bs):
    if not is_pe(bs):
        return nil
    end
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
end

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
end

# Parse optional header (variable size, after COFF header)
proc parse_optional_header(bs, pe_off, opt_size):
    if opt_size == 0:
        return nil
    end
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
        # Parse data directories (PE32+: start at offset 112)
        let dd_off = off + 112
        if opt["num_data_directories"] > 0:
            opt["export_table_rva"] = read_u32_le(bs, dd_off)
            opt["export_table_size"] = read_u32_le(bs, dd_off + 4)
        end
        if opt["num_data_directories"] > 1:
            opt["import_table_rva"] = read_u32_le(bs, dd_off + 8)
            opt["import_table_size"] = read_u32_le(bs, dd_off + 12)
        end
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
        # Parse data directories (PE32: start at offset 96)
        let dd_off = off + 96
        if opt["num_data_directories"] > 0:
            opt["export_table_rva"] = read_u32_le(bs, dd_off)
            opt["export_table_size"] = read_u32_le(bs, dd_off + 4)
        end
        if opt["num_data_directories"] > 1:
            opt["import_table_rva"] = read_u32_le(bs, dd_off + 8)
            opt["import_table_size"] = read_u32_le(bs, dd_off + 12)
        end
    end

    return opt
end

# Read an 8-byte section name (null-padded ASCII)
proc read_section_name(bs, off):
    let name = ""
    for i in range(8):
        if bs[off + i] == 0:
            return name
        end
        name = name + chr(bs[off + i])
    end
    return name
end

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
end

# Parse all section headers
proc parse_sections(bs, pe_off, coff):
    let sections = []
    let off = pe_off + 24 + coff["optional_header_size"]
    for i in range(coff["num_sections"]):
        push(sections, parse_section(bs, off + i * 40))
    end
    return sections
end

# High-level: parse entire PE file
proc parse_pe(bs):
    let dos = parse_dos_header(bs)
    if dos == nil:
        return nil
    end
    let pe_off = dos["e_lfanew"]
    # Verify PE signature
    if read_u32_le(bs, pe_off) != 17744:
        return nil
    end
    let pe = {}
    pe["dos"] = dos
    pe["pe_offset"] = pe_off
    pe["coff"] = parse_coff_header(bs, pe_off)
    pe["optional"] = parse_optional_header(bs, pe_off, pe["coff"]["optional_header_size"])
    pe["sections"] = parse_sections(bs, pe_off, pe["coff"])
    return pe
end

# Find a section by name
proc find_section(pe, name):
    let sections = pe["sections"]
    for i in range(len(sections)):
        if sections[i]["name"] == name:
            return sections[i]
        end
    end
    return nil
end

# Check if PE is a UEFI application
@inline
proc is_uefi_app(pe):
    if pe["optional"] == nil:
        return false
    end
    let sub = pe["optional"]["subsystem"]
    return sub == 10 or sub == 11 or sub == 12
end

# Read raw bytes from a section
proc section_data(bs, section):
    let data = []
    let off = section["raw_data_offset"]
    let sz = section["raw_data_size"]
    for i in range(sz):
        push(data, bs[off + i])
    end
    return data
end

# ========== Import Table ==========

proc parse_imports(bs, pe):
    let imports = []
    if pe["optional"] == nil:
        return imports
    end
    if not dict_has(pe["optional"], "import_table_rva"):
        return imports
    end
    let import_rva = pe["optional"]["import_table_rva"]
    if import_rva == 0:
        return imports
    end
    # Find section containing import RVA
    let import_off = rva_to_offset(bs, pe, import_rva)
    if import_off < 0:
        return imports
    end
    # Parse Import Directory Table (20-byte entries)
    let off = import_off
    while off + 20 <= len(bs):
        let ilt_rva = read_u32_le(bs, off)
        let timestamp = read_u32_le(bs, off + 4)
        let forwarder = read_u32_le(bs, off + 8)
        let name_rva = read_u32_le(bs, off + 12)
        let iat_rva = read_u32_le(bs, off + 16)
        if ilt_rva == 0 and name_rva == 0:
            break
        end
        let entry = {}
        let name_off = rva_to_offset(bs, pe, name_rva)
        if name_off >= 0:
            entry["dll_name"] = read_string_pe(bs, name_off)
        else:
            entry["dll_name"] = ""
        end
        entry["ilt_rva"] = ilt_rva
        entry["iat_rva"] = iat_rva
        entry["timestamp"] = timestamp
        entry["functions"] = []
        # Parse ILT entries (import lookup table)
        let ilt_off = rva_to_offset(bs, pe, ilt_rva)
        if ilt_off >= 0:
            let is_64 = pe["optional"]["magic"] == 523
            let entry_size = 4
            if is_64:
                entry_size = 8
            end
            let foff = ilt_off
            while foff + entry_size <= len(bs):
                let fval = 0
                if is_64:
                    fval = read_u64_le(bs, foff)
                else:
                    fval = read_u32_le(bs, foff)
                end
                if fval == 0:
                    break
                end
                let func = {}
                # Check ordinal bit
                let ordinal_flag = false
                if is_64:
                    ordinal_flag = (fval >> 63) != 0
                else:
                    ordinal_flag = (fval >> 31) != 0
                end
                if ordinal_flag:
                    func["ordinal"] = fval & 65535
                    func["name"] = ""
                else:
                    let hint_off = rva_to_offset(bs, pe, fval & 2147483647)
                    if hint_off >= 0:
                        func["hint"] = read_u16_le(bs, hint_off)
                        func["name"] = read_string_pe(bs, hint_off + 2)
                    else:
                        func["name"] = ""
                    end
                end
                push(entry["functions"], func)
                foff = foff + entry_size
            end
        end
        push(imports, entry)
        off = off + 20
    end
    return imports
end

# ========== Export Table ==========

proc parse_exports(bs, pe):
    let result = {}
    result["functions"] = []
    if pe["optional"] == nil:
        return result
    end
    if not dict_has(pe["optional"], "export_table_rva"):
        return result
    end
    let export_rva = pe["optional"]["export_table_rva"]
    if export_rva == 0:
        return result
    end
    let off = rva_to_offset(bs, pe, export_rva)
    if off < 0:
        return result
    end
    result["characteristics"] = read_u32_le(bs, off)
    result["timestamp"] = read_u32_le(bs, off + 4)
    let name_rva = read_u32_le(bs, off + 12)
    result["ordinal_base"] = read_u32_le(bs, off + 16)
    result["num_functions"] = read_u32_le(bs, off + 20)
    result["num_names"] = read_u32_le(bs, off + 24)
    let func_rva = read_u32_le(bs, off + 28)
    let name_ptr_rva = read_u32_le(bs, off + 32)
    let ordinal_rva = read_u32_le(bs, off + 36)
    let name_off = rva_to_offset(bs, pe, name_rva)
    if name_off >= 0:
        result["dll_name"] = read_string_pe(bs, name_off)
    end
    # Parse exported names
    let name_ptr_off = rva_to_offset(bs, pe, name_ptr_rva)
    let ordinal_off = rva_to_offset(bs, pe, ordinal_rva)
    if name_ptr_off >= 0 and ordinal_off >= 0:
        for i in range(result["num_names"]):
            let fn = {}
            let fn_name_rva = read_u32_le(bs, name_ptr_off + i * 4)
            let fn_name_off = rva_to_offset(bs, pe, fn_name_rva)
            if fn_name_off >= 0:
                fn["name"] = read_string_pe(bs, fn_name_off)
            else:
                fn["name"] = ""
            end
            fn["ordinal"] = read_u16_le(bs, ordinal_off + i * 2) + result["ordinal_base"]
            push(result["functions"], fn)
        end
    end
    return result
end

# ========== Helper functions ==========

proc rva_to_offset(bs, pe, rva):
    for i in range(len(pe["sections"])):
        let sec = pe["sections"][i]
        if rva >= sec["virtual_address"] and rva < sec["virtual_address"] + sec["virtual_size"]:
            return sec["raw_data_offset"] + (rva - sec["virtual_address"])
        end
    end
    return -1
end

proc read_string_pe(bs, off):
    let s = ""
    while off < len(bs):
        if bs[off] == 0:
            break
        end
        s = s + chr(bs[off])
        off = off + 1
    end
    return s
end

# ========== Resource Directory ==========

proc parse_resource_dir(bs, pe, rva, level):
    let off = rva_to_offset(bs, pe, rva)
    if off < 0:
        return nil
    end
    let dir = {}
    dir["characteristics"] = read_u32_le(bs, off)
    dir["timestamp"] = read_u32_le(bs, off + 4)
    dir["major_version"] = read_u16_le(bs, off + 8)
    dir["minor_version"] = read_u16_le(bs, off + 10)
    let num_named = read_u16_le(bs, off + 12)
    let num_id = read_u16_le(bs, off + 14)
    dir["entries"] = []
    let entry_off = off + 16
    for i in range(num_named + num_id):
        let e = {}
        e["name_or_id"] = read_u32_le(bs, entry_off)
        e["data_or_subdir"] = read_u32_le(bs, entry_off + 4)
        e["is_name"] = (e["name_or_id"] >> 31) != 0
        e["is_subdir"] = (e["data_or_subdir"] >> 31) != 0
        if not e["is_name"]:
            e["id"] = e["name_or_id"]
        end
        push(dir["entries"], e)
        entry_off = entry_off + 8
    end
    return dir
end
