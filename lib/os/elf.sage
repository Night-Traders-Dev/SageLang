gc_disable()
# ELF (Executable and Linkable Format) binary parser
# Supports ELF32 and ELF64 headers, program headers, and section headers

proc read_u16_le(bs, off):
    return bs[off] + bs[off + 1] * 256

proc read_u32_le(bs, off):
    return bs[off] + bs[off + 1] * 256 + bs[off + 2] * 65536 + bs[off + 3] * 16777216

proc read_u64_le(bs, off):
    let lo = read_u32_le(bs, off)
    let hi = read_u32_le(bs, off + 4)
    return lo + hi * 4294967296

proc read_u16_be(bs, off):
    return bs[off] * 256 + bs[off + 1]

proc read_u32_be(bs, off):
    return bs[off] * 16777216 + bs[off + 1] * 65536 + bs[off + 2] * 256 + bs[off + 3]

# ELF magic: 0x7f 'E' 'L' 'F'
proc is_elf(bs):
    if len(bs) < 16:
        return false
    if bs[0] != 127:
        return false
    if bs[1] != 69:
        return false
    if bs[2] != 76:
        return false
    if bs[3] != 70:
        return false
    return true

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
    if t == 1:
        return "REL"
    if t == 2:
        return "EXEC"
    if t == 3:
        return "DYN"
    if t == 4:
        return "CORE"
    return "UNKNOWN"

proc elf_machine_name(m):
    if m == 0:
        return "NONE"
    if m == 3:
        return "i386"
    if m == 40:
        return "ARM"
    if m == 62:
        return "x86_64"
    if m == 183:
        return "AArch64"
    if m == 243:
        return "RISC-V"
    return "UNKNOWN"

proc phdr_type_name(t):
    if t == 0:
        return "NULL"
    if t == 1:
        return "LOAD"
    if t == 2:
        return "DYNAMIC"
    if t == 3:
        return "INTERP"
    if t == 4:
        return "NOTE"
    if t == 6:
        return "PHDR"
    if t == 7:
        return "TLS"
    return "UNKNOWN"

proc shdr_type_name(t):
    if t == 0:
        return "NULL"
    if t == 1:
        return "PROGBITS"
    if t == 2:
        return "SYMTAB"
    if t == 3:
        return "STRTAB"
    if t == 4:
        return "RELA"
    if t == 5:
        return "HASH"
    if t == 6:
        return "DYNAMIC"
    if t == 7:
        return "NOTE"
    if t == 8:
        return "NOBITS"
    if t == 9:
        return "REL"
    if t == 11:
        return "DYNSYM"
    return "UNKNOWN"

# Parse the ELF identification header (first 16 bytes)
proc parse_ident(bs):
    if not is_elf(bs):
        return nil
    let ident = {}
    ident["ei_class"] = bs[4]
    ident["ei_data"] = bs[5]
    ident["ei_version"] = bs[6]
    ident["ei_osabi"] = bs[7]
    ident["ei_abiversion"] = bs[8]
    if bs[4] == 1:
        ident["class_name"] = "ELF32"
    if bs[4] == 2:
        ident["class_name"] = "ELF64"
    if bs[5] == 1:
        ident["encoding"] = "LSB"
    if bs[5] == 2:
        ident["encoding"] = "MSB"
    return ident

# Parse ELF header (works for both ELF32 and ELF64)
proc parse_header(bs):
    let ident = parse_ident(bs)
    if ident == nil:
        return nil
    let is_64 = ident["ei_class"] == 2
    let is_le = ident["ei_data"] == 1
    let r16 = read_u16_le
    let r32 = read_u32_le
    let r64 = read_u64_le
    if not is_le:
        r16 = read_u16_be
        r32 = read_u32_be

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

    return hdr

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

    return ph

# Parse all program headers
proc parse_phdrs(bs, hdr):
    let phdrs = []
    for i in range(hdr["phnum"]):
        push(phdrs, parse_phdr(bs, hdr, i))
    return phdrs

# Parse a single section header
proc parse_shdr(bs, hdr, index):
    let off = hdr["shoff"] + index * hdr["shentsize"]
    let is_64 = hdr["is_64"]
    let is_le = hdr["is_le"]
    let r32 = read_u32_le
    let r64 = read_u64_le
    if not is_le:
        r32 = read_u32_be

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

    return sh

# Parse all section headers
proc parse_shdrs(bs, hdr):
    let shdrs = []
    for i in range(hdr["shnum"]):
        push(shdrs, parse_shdr(bs, hdr, i))
    return shdrs

# Read a null-terminated string from byte array at offset
proc read_string(bs, off):
    let result = ""
    let i = off
    while i < len(bs):
        if bs[i] == 0:
            return result
        result = result + chr(bs[i])
        i = i + 1
    return result

# Read section name from string table
proc section_name(bs, hdr, shdr):
    let strtab_shdr = parse_shdr(bs, hdr, hdr["shstrndx"])
    let str_off = strtab_shdr["offset"] + shdr["name_offset"]
    return read_string(bs, str_off)

# Find a section by name
proc find_section(bs, hdr, name):
    let shdrs = parse_shdrs(bs, hdr)
    for i in range(len(shdrs)):
        let sname = section_name(bs, hdr, shdrs[i])
        if sname == name:
            return shdrs[i]
    return nil

# Read raw bytes from a section
proc section_data(bs, shdr):
    let data = []
    let off = shdr["offset"]
    let sz = shdr["size"]
    for i in range(sz):
        push(data, bs[off + i])
    return data
