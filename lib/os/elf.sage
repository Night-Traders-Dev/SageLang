gc_disable()
# ELF (Executable and Linkable Format) binary parser
# Supports ELF32 and ELF64 headers, program headers, and section headers

proc read_u16_le(bs, off):
    return bs[off] + bs[off + 1] * 256
end

proc read_u32_le(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216
end

proc read_u64_le(bs, off):
    let lo = read_u32_le(bs, off)
    let hi = read_u32_le(bs, off + 4)
    return lo + hi * 4294967296
end

proc read_u16_be(bs, off):
    return bs[off] * 256 + bs[off + 1]
end

proc read_u32_be(bs, off):
    return bs[off] * 16777216 + bs[off + 1] * 65536 + bs[off + 2] * 256 + bs[off + 3]
end

proc read_u64_be(bs, off):
    let hi = read_u32_be(bs, off)
    let lo = read_u32_be(bs, off + 4)
    return lo + hi * 4294967296
end

# ELF magic: 0x7f 'E' 'L' 'F'
proc is_elf(bs):
    if len(bs) < 16:
        return false
    end
    if bs[0] != 127:
        return false
    end
    if bs[1] != 69:
        return false
    end
    if bs[2] != 76:
        return false
    end
    if bs[3] != 70:
        return false
    end
    return true
end

# ELF class constants
let ELFCLASS32 = 1
let ELFCLASS64 = 2

# ELF data encoding
let ELFDATA2LSB = 1
let ELFDATA2MSB = 2

# ELF type constants
let ET_NONE = 0
let ET_REL = 1
let ET_EXEC = 2
let ET_DYN = 3
let ET_CORE = 4

# ELF machine constants
let EM_NONE = 0
let EM_386 = 3
let EM_ARM = 40
let EM_X86_64 = 62
let EM_AARCH64 = 183
let EM_RISCV = 243

# Program header type constants
let PT_NULL = 0
let PT_LOAD = 1
let PT_DYNAMIC = 2
let PT_INTERP = 3
let PT_NOTE = 4
let PT_PHDR = 6
let PT_TLS = 7

# Section header type constants
let SHT_NULL = 0
let SHT_PROGBITS = 1
let SHT_SYMTAB = 2
let SHT_STRTAB = 3
let SHT_RELA = 4
let SHT_HASH = 5
let SHT_DYNAMIC = 6
let SHT_NOTE = 7
let SHT_NOBITS = 8
let SHT_REL = 9
let SHT_DYNSYM = 11

# Section header flag constants
let SHF_WRITE = 1
let SHF_ALLOC = 2
let SHF_EXECINSTR = 4

proc elf_type_name(t):
    if t == 0:
        return "NONE"
    end
    if t == 1:
        return "REL"
    end
    if t == 2:
        return "EXEC"
    end
    if t == 3:
        return "DYN"
    end
    if t == 4:
        return "CORE"
    end
    return "UNKNOWN"
end

proc elf_machine_name(m):
    if m == 0:
        return "NONE"
    end
    if m == 3:
        return "i386"
    end
    if m == 40:
        return "ARM"
    end
    if m == 62:
        return "x86_64"
    end
    if m == 183:
        return "AArch64"
    end
    if m == 243:
        return "RISC-V"
    end
    return "UNKNOWN"
end

proc phdr_type_name(t):
    if t == 0:
        return "NULL"
    end
    if t == 1:
        return "LOAD"
    end
    if t == 2:
        return "DYNAMIC"
    end
    if t == 3:
        return "INTERP"
    end
    if t == 4:
        return "NOTE"
    end
    if t == 6:
        return "PHDR"
    end
    if t == 7:
        return "TLS"
    end
    return "UNKNOWN"
end

proc shdr_type_name(t):
    if t == 0:
        return "NULL"
    end
    if t == 1:
        return "PROGBITS"
    end
    if t == 2:
        return "SYMTAB"
    end
    if t == 3:
        return "STRTAB"
    end
    if t == 4:
        return "RELA"
    end
    if t == 5:
        return "HASH"
    end
    if t == 6:
        return "DYNAMIC"
    end
    if t == 7:
        return "NOTE"
    end
    if t == 8:
        return "NOBITS"
    end
    if t == 9:
        return "REL"
    end
    if t == 11:
        return "DYNSYM"
    end
    return "UNKNOWN"
end

# Parse the ELF identification header (first 16 bytes)
proc parse_ident(bs):
    if not is_elf(bs):
        return nil
    end
    let ident = {}
    ident["ei_class"] = bs[4]
    ident["ei_data"] = bs[5]
    ident["ei_version"] = bs[6]
    ident["ei_osabi"] = bs[7]
    ident["ei_abiversion"] = bs[8]
    if bs[4] == 1:
        ident["class_name"] = "ELF32"
    end
    if bs[4] == 2:
        ident["class_name"] = "ELF64"
    end
    if bs[5] == 1:
        ident["encoding"] = "LSB"
    end
    if bs[5] == 2:
        ident["encoding"] = "MSB"
    end
    return ident
end

# Parse ELF header (works for both ELF32 and ELF64)
proc parse_header(bs):
    let ident = parse_ident(bs)
    if ident == nil:
        return nil
    end
    let is_64 = ident["ei_class"] == 2
    let is_le = ident["ei_data"] == 1
    let r16 = read_u16_le
    let r32 = read_u32_le
    let r64 = read_u64_le
    if not is_le:
        r16 = read_u16_be
        r32 = read_u32_be
        r64 = read_u64_be
    end

    let hdr = {}
    hdr["ident"] = ident
    hdr["is_64"] = is_64
    hdr["is_le"] = is_le
    hdr["type"] = r16(bs, 16)
    hdr["type_name"] = elf_type_name(r16(bs, 16))
    hdr["machine"] = r16(bs, 18)
    hdr["machine_name"] = elf_machine_name(r16(bs, 18))
    hdr["version"] = r32(bs, 20)

    if is_64:
        hdr["entry"] = r64(bs, 24)
        hdr["phoff"] = r64(bs, 32)
        hdr["shoff"] = r64(bs, 40)
        hdr["flags"] = r32(bs, 48)
        hdr["ehsize"] = r16(bs, 52)
        hdr["phentsize"] = r16(bs, 54)
        hdr["phnum"] = r16(bs, 56)
        hdr["shentsize"] = r16(bs, 58)
        hdr["shnum"] = r16(bs, 60)
        hdr["shstrndx"] = r16(bs, 62)
    else:
        hdr["entry"] = r32(bs, 24)
        hdr["phoff"] = r32(bs, 28)
        hdr["shoff"] = r32(bs, 32)
        hdr["flags"] = r32(bs, 36)
        hdr["ehsize"] = r16(bs, 40)
        hdr["phentsize"] = r16(bs, 42)
        hdr["phnum"] = r16(bs, 44)
        hdr["shentsize"] = r16(bs, 46)
        hdr["shnum"] = r16(bs, 48)
        hdr["shstrndx"] = r16(bs, 50)
    end

    return hdr
end

# Parse a single program header
proc parse_phdr(bs, hdr, index):
    let off = hdr["phoff"] + index * hdr["phentsize"]
    let is_64 = hdr["is_64"]
    let is_le = hdr["is_le"]
    let r16 = read_u16_le
    let r32 = read_u32_le
    let r64 = read_u64_le
    if not is_le:
        r16 = read_u16_be
        r32 = read_u32_be
        r64 = read_u64_be
    end

    let ph = {}
    ph["type"] = r32(bs, off)
    ph["type_name"] = phdr_type_name(r32(bs, off))

    if is_64:
        ph["flags"] = r32(bs, off + 4)
        ph["offset"] = r64(bs, off + 8)
        ph["vaddr"] = r64(bs, off + 16)
        ph["paddr"] = r64(bs, off + 24)
        ph["filesz"] = r64(bs, off + 32)
        ph["memsz"] = r64(bs, off + 40)
        ph["align"] = r64(bs, off + 48)
    else:
        ph["offset"] = r32(bs, off + 4)
        ph["vaddr"] = r32(bs, off + 8)
        ph["paddr"] = r32(bs, off + 12)
        ph["filesz"] = r32(bs, off + 16)
        ph["memsz"] = r32(bs, off + 20)
        ph["flags"] = r32(bs, off + 24)
        ph["align"] = r32(bs, off + 28)
    end

    return ph
end

# Parse all program headers
proc parse_phdrs(bs, hdr):
    let phdrs = []
    for i in range(hdr["phnum"]):
        push(phdrs, parse_phdr(bs, hdr, i))
    end
    return phdrs
end

# Parse a single section header
proc parse_shdr(bs, hdr, index):
    let off = hdr["shoff"] + index * hdr["shentsize"]
    let is_64 = hdr["is_64"]
    let is_le = hdr["is_le"]
    let r32 = read_u32_le
    let r64 = read_u64_le
    if not is_le:
        r32 = read_u32_be
        r64 = read_u64_be
    end

    let sh = {}
    sh["name_offset"] = r32(bs, off)
    sh["type"] = r32(bs, off + 4)
    sh["type_name"] = shdr_type_name(r32(bs, off + 4))

    if is_64:
        sh["flags"] = r64(bs, off + 8)
        sh["addr"] = r64(bs, off + 16)
        sh["offset"] = r64(bs, off + 24)
        sh["size"] = r64(bs, off + 32)
        sh["link"] = r32(bs, off + 40)
        sh["info"] = r32(bs, off + 44)
        sh["addralign"] = r64(bs, off + 48)
        sh["entsize"] = r64(bs, off + 56)
    else:
        sh["flags"] = r32(bs, off + 8)
        sh["addr"] = r32(bs, off + 12)
        sh["offset"] = r32(bs, off + 16)
        sh["size"] = r32(bs, off + 20)
        sh["link"] = r32(bs, off + 24)
        sh["info"] = r32(bs, off + 28)
        sh["addralign"] = r32(bs, off + 32)
        sh["entsize"] = r32(bs, off + 36)
    end

    return sh
end

# Parse all section headers
proc parse_shdrs(bs, hdr):
    let shdrs = []
    for i in range(hdr["shnum"]):
        push(shdrs, parse_shdr(bs, hdr, i))
    end
    return shdrs
end

# Read a null-terminated string from byte array at offset
proc read_string(bs, off):
    let result = ""
    let i = off
    while i < len(bs):
        if bs[i] == 0:
            return result
        end
        result = result + chr(bs[i])
        i = i + 1
    end
    return result
end

# Read section name from string table
proc section_name(bs, hdr, shdr):
    let strtab_shdr = parse_shdr(bs, hdr, hdr["shstrndx"])
    let str_off = strtab_shdr["offset"] + shdr["name_offset"]
    return read_string(bs, str_off)
end

# Find a section by name
proc find_section(bs, hdr, name):
    let shdrs = parse_shdrs(bs, hdr)
    for i in range(len(shdrs)):
        let sname = section_name(bs, hdr, shdrs[i])
        if sname == name:
            return shdrs[i]
        end
    end
    return nil
end

# Read raw bytes from a section
proc section_data(bs, shdr):
    let data = []
    let off = shdr["offset"]
    let sz = shdr["size"]
    for i in range(sz):
        push(data, bs[off + i])
    end
    return data
end

# ========== Symbol Table ==========

proc parse_symbol_32(bs, off):
    let sym = {}
    sym["name_offset"] = read_u32_le(bs, off)
    sym["value"] = read_u32_le(bs, off + 4)
    sym["size"] = read_u32_le(bs, off + 8)
    sym["info"] = bs[off + 12]
    sym["other"] = bs[off + 13]
    sym["shndx"] = read_u16_le(bs, off + 14)
    sym["bind"] = (sym["info"] >> 4) & 15
    sym["type"] = sym["info"] & 15
    sym["visibility"] = sym["other"] & 3
    return sym
end

proc parse_symbol_64(bs, off):
    let sym = {}
    sym["name_offset"] = read_u32_le(bs, off)
    sym["info"] = bs[off + 4]
    sym["other"] = bs[off + 5]
    sym["shndx"] = read_u16_le(bs, off + 6)
    sym["value"] = read_u64_le(bs, off + 8)
    sym["size"] = read_u64_le(bs, off + 16)
    sym["bind"] = (sym["info"] >> 4) & 15
    sym["type"] = sym["info"] & 15
    sym["visibility"] = sym["other"] & 3
    return sym
end

proc sym_bind_name(b):
    if b == 0:
        return "LOCAL"
    end
    if b == 1:
        return "GLOBAL"
    end
    if b == 2:
        return "WEAK"
    end
    return "UNKNOWN"
end

proc sym_type_name(t):
    if t == 0:
        return "NOTYPE"
    end
    if t == 1:
        return "OBJECT"
    end
    if t == 2:
        return "FUNC"
    end
    if t == 3:
        return "SECTION"
    end
    if t == 4:
        return "FILE"
    end
    if t == 10:
        return "IFUNC"
    end
    return "UNKNOWN"
end

# Parse all symbols from .symtab or .dynsym
proc parse_symbols(bs, hdr, section_name_str):
    let shdr = find_section(bs, hdr, section_name_str)
    if shdr == nil:
        return []
    end
    let syms = []
    let entry_size = shdr["entsize"]
    if entry_size == 0:
        if hdr["ident"]["ei_class"] == 1:
            entry_size = 16
        else:
            entry_size = 24
        end
    end
    let count = (shdr["size"] / entry_size) | 0
    # Find associated string table
    let strtab_shdr = parse_shdr(bs, hdr, shdr["link"])
    for i in range(count):
        let off = shdr["offset"] + i * entry_size
        let sym = nil
        if hdr["ident"]["ei_class"] == 1:
            sym = parse_symbol_32(bs, off)
        else:
            sym = parse_symbol_64(bs, off)
        end
        # Resolve name
        sym["name"] = read_string(bs, strtab_shdr["offset"] + sym["name_offset"])
        sym["bind_name"] = sym_bind_name(sym["bind"])
        sym["type_name"] = sym_type_name(sym["type"])
        push(syms, sym)
    end
    return syms
end

proc get_symtab(bs, hdr):
    return parse_symbols(bs, hdr, ".symtab")
end

proc get_dynsym(bs, hdr):
    return parse_symbols(bs, hdr, ".dynsym")
end

# Find a symbol by name
proc find_symbol(symbols, name):
    for i in range(len(symbols)):
        if symbols[i]["name"] == name:
            return symbols[i]
        end
    end
    return nil
end

# ========== Relocations ==========

proc parse_rela_64(bs, off):
    let rel = {}
    rel["offset"] = read_u64_le(bs, off)
    let info = read_u64_le(bs, off + 8)
    rel["sym_idx"] = (info >> 32) & 4294967295
    rel["type"] = info & 4294967295
    rel["addend"] = read_u64_le(bs, off + 16)
    return rel
end

proc parse_rel_64(bs, off):
    let rel = {}
    rel["offset"] = read_u64_le(bs, off)
    let info = read_u64_le(bs, off + 8)
    rel["sym_idx"] = (info >> 32) & 4294967295
    rel["type"] = info & 4294967295
    rel["addend"] = 0
    return rel
end

proc rela_type_name_x64(t):
    if t == 0:
        return "R_X86_64_NONE"
    end
    if t == 1:
        return "R_X86_64_64"
    end
    if t == 2:
        return "R_X86_64_PC32"
    end
    if t == 4:
        return "R_X86_64_PLT32"
    end
    if t == 7:
        return "R_X86_64_JUMP_SLOT"
    end
    if t == 8:
        return "R_X86_64_RELATIVE"
    end
    if t == 10:
        return "R_X86_64_32"
    end
    if t == 11:
        return "R_X86_64_32S"
    end
    return "R_X86_64_" + str(t)
end

proc parse_relocations(bs, hdr, rela_section):
    let rels = []
    if rela_section == nil:
        return rels
    end
    let entry_size = rela_section["entsize"]
    if entry_size == 0:
        entry_size = 24
    end
    let is_rela = (rela_section["type"] == 4)
    let count = (rela_section["size"] / entry_size) | 0
    for i in range(count):
        let off = rela_section["offset"] + i * entry_size
        let rel = nil
        if is_rela:
            rel = parse_rela_64(bs, off)
        else:
            rel = parse_rel_64(bs, off)
        end
        rel["type_name"] = rela_type_name_x64(rel["type"])
        push(rels, rel)
    end
    return rels
end

# Get all relocations from .rela.text, .rela.plt, etc.
proc get_all_relocations(bs, hdr):
    let all_rels = []
    let shdrs = parse_shdrs(bs, hdr)
    for i in range(len(shdrs)):
        if shdrs[i]["type"] == 4 or shdrs[i]["type"] == 9:
            let rels = parse_relocations(bs, hdr, shdrs[i])
            let sec_name = section_name(bs, hdr, shdrs[i])
            for j in range(len(rels)):
                rels[j]["section"] = sec_name
                push(all_rels, rels[j])
            end
        end
    end
    return all_rels
end

# ========== Dynamic Linking ==========

proc parse_dynamic(bs, hdr):
    let entries = []
    let shdr = find_section(bs, hdr, ".dynamic")
    if shdr == nil:
        return entries
    end
    let off = shdr["offset"]
    let end_off = off + shdr["size"]
    while off + 16 <= end_off:
        let tag = read_u64_le(bs, off)
        let val = read_u64_le(bs, off + 8)
        if tag == 0:
            break
        end
        let entry = {}
        entry["tag"] = tag
        entry["value"] = val
        if tag == 1:
            entry["tag_name"] = "DT_NEEDED"
        end
        if tag == 5:
            entry["tag_name"] = "DT_STRTAB"
        end
        if tag == 6:
            entry["tag_name"] = "DT_SYMTAB"
        end
        if tag == 7:
            entry["tag_name"] = "DT_RELA"
        end
        if tag == 10:
            entry["tag_name"] = "DT_STRSZ"
        end
        if tag == 14:
            entry["tag_name"] = "DT_SONAME"
        end
        if tag == 15:
            entry["tag_name"] = "DT_RPATH"
        end
        if tag == 23:
            entry["tag_name"] = "DT_JMPREL"
        end
        if not dict_has(entry, "tag_name"):
            entry["tag_name"] = "DT_" + str(tag)
        end
        push(entries, entry)
        off = off + 16
    end
    return entries
end

# Get shared library dependencies (DT_NEEDED)
proc get_needed_libs(bs, hdr):
    let libs = []
    let dyn = parse_dynamic(bs, hdr)
    let strtab = find_section(bs, hdr, ".dynstr")
    if strtab == nil:
        return libs
    end
    for i in range(len(dyn)):
        if dyn[i]["tag"] == 1:
            let name = read_string(bs, strtab["offset"] + dyn[i]["value"])
            push(libs, name)
        end
    end
    return libs
end

# ========== ELF Writer (minimal) ==========

proc create_elf64_header(entry, phnum, shnum):
    let hdr = []
    # ELF magic
    push(hdr, 127)
    push(hdr, 69)
    push(hdr, 76)
    push(hdr, 70)
    push(hdr, 2)
    push(hdr, 1)
    push(hdr, 1)
    push(hdr, 0)
    for i in range(8):
        push(hdr, 0)
    end
    # e_type = ET_EXEC (2)
    push(hdr, 2)
    push(hdr, 0)
    # e_machine = x86_64 (62)
    push(hdr, 62)
    push(hdr, 0)
    # e_version
    push(hdr, 1)
    push(hdr, 0)
    push(hdr, 0)
    push(hdr, 0)
    # e_entry (8 bytes)
    for i in range(8):
        push(hdr, (entry >> (i * 8)) & 255)
    end
    # e_phoff = 64
    push(hdr, 64)
    for i in range(7):
        push(hdr, 0)
    end
    # e_shoff = 0 (no sections)
    for i in range(8):
        push(hdr, 0)
    end
    # e_flags
    for i in range(4):
        push(hdr, 0)
    end
    # e_ehsize = 64
    push(hdr, 64)
    push(hdr, 0)
    # e_phentsize = 56
    push(hdr, 56)
    push(hdr, 0)
    # e_phnum
    push(hdr, phnum & 255)
    push(hdr, (phnum >> 8) & 255)
    # e_shentsize = 64
    push(hdr, 64)
    push(hdr, 0)
    # e_shnum
    push(hdr, shnum & 255)
    push(hdr, (shnum >> 8) & 255)
    # e_shstrndx
    push(hdr, 0)
    push(hdr, 0)
    return hdr
end
