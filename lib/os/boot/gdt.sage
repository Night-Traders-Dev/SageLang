gc_disable()

# Global Descriptor Table (GDT) for x86_64
# Defines segment descriptors for protected/long mode transitions

# --- Access byte bit constants ---
let PRESENT = 128
let DPL0 = 0
let DPL1 = 32
let DPL2 = 64
let DPL3 = 96
let CODE = 24
let DATA = 16
let EXECUTABLE = 8
let RW = 2
let ACCESSED = 1
let LONG_MODE = 32
let SIZE_32 = 64
let GRANULARITY = 128

# --- TSS type ---
let TSS_AVAILABLE = 9
let TSS_BUSY = 11

# --- Helper: push a single byte ---
proc push_byte(arr, val):
    push(arr, val % 256)
end

# --- Helper: push 2 bytes little-endian ---
proc push_u16(arr, val):
    let v = val
    push(arr, v % 256)
    v = (v - (v % 256)) / 256
    push(arr, v % 256)
end

# --- Helper: push 4 bytes little-endian ---
proc push_u32(arr, val):
    let v = val
    push(arr, v % 256)
    v = (v - (v % 256)) / 256
    push(arr, v % 256)
    v = (v - (v % 256)) / 256
    push(arr, v % 256)
    v = (v - (v % 256)) / 256
    push(arr, v % 256)
end

# --- Create a GDT entry (8 bytes) ---
# base: 32-bit base address
# limit: 20-bit limit
# access: access byte
# flags: 4-bit flags (upper nibble of byte 6)
proc create_entry(base, limit, access, flags):
    let entry = []
    # Byte 0-1: limit bits 0-15
    push_u16(entry, limit % 65536)
    # Byte 2-3: base bits 0-15
    push_u16(entry, base % 65536)
    # Byte 4: base bits 16-23
    let base_mid = ((base - (base % 65536)) / 65536) % 256
    push_byte(entry, base_mid)
    # Byte 5: access byte
    push_byte(entry, access)
    # Byte 6: flags (upper 4 bits) + limit bits 16-19 (lower 4 bits)
    let limit_hi = ((limit - (limit % 65536)) / 65536) % 16
    let flags_shifted = (flags % 16) * 16
    push_byte(entry, flags_shifted + limit_hi)
    # Byte 7: base bits 24-31
    let base_hi = ((base - (base % 16777216)) / 16777216) % 256
    push_byte(entry, base_hi)
    return entry
end

# --- Null descriptor ---
proc null_entry():
    return create_entry(0, 0, 0, 0)
end

# --- Kernel code segment (ring 0, 64-bit) ---
proc kernel_code_entry():
    # access: Present + DPL0 + Code + Executable + RW = 0x9A
    # flags: Long mode = 0x20 -> upper nibble = 0x2
    let access = PRESENT + DPL0 + CODE + EXECUTABLE + RW
    return create_entry(0, 1048575, access, 2)
end

# --- Kernel data segment (ring 0) ---
proc kernel_data_entry():
    # access: Present + DPL0 + Data + RW = 0x92
    # flags: 0x00
    let access = PRESENT + DPL0 + DATA + RW
    return create_entry(0, 1048575, access, 0)
end

# --- User code segment (ring 3, 64-bit) ---
proc user_code_entry():
    # access: Present + DPL3 + Code + Executable + RW = 0xFA
    # flags: Long mode = 0x2
    let access = PRESENT + DPL3 + CODE + EXECUTABLE + RW
    return create_entry(0, 1048575, access, 2)
end

# --- User data segment (ring 3) ---
proc user_data_entry():
    # access: Present + DPL3 + Data + RW = 0xF2
    # flags: 0x00
    let access = PRESENT + DPL3 + DATA + RW
    return create_entry(0, 1048575, access, 0)
end

# --- TSS descriptor (16 bytes in long mode) ---
proc tss_entry(base, limit):
    let entry = []
    # First 8 bytes: standard descriptor with TSS type
    let access = PRESENT + DPL0 + TSS_AVAILABLE
    let first = create_entry(base, limit, access, 0)
    let i = 0
    for i in range(len(first)):
        push(entry, first[i])
    end
    # Next 4 bytes: base bits 32-63
    let base_upper = 0
    push_u32(entry, base_upper)
    # Reserved 4 bytes
    push_u32(entry, 0)
    return entry
end

# --- Create a complete GDT ---
proc create_gdt():
    let gdt = {}
    gdt["entries"] = []
    # 0: Null descriptor
    push(gdt["entries"], null_entry())
    # 1: Kernel code (selector 0x08)
    push(gdt["entries"], kernel_code_entry())
    # 2: Kernel data (selector 0x10)
    push(gdt["entries"], kernel_data_entry())
    # 3: User code (selector 0x18 | 3 = 0x1B)
    push(gdt["entries"], user_code_entry())
    # 4: User data (selector 0x20 | 3 = 0x23)
    push(gdt["entries"], user_data_entry())
    gdt["kernel_code_sel"] = 8
    gdt["kernel_data_sel"] = 16
    gdt["user_code_sel"] = 27
    gdt["user_data_sel"] = 35
    return gdt
end

# --- Serialize GDT to flat byte array ---
proc serialize(gdt):
    let bytes = []
    let entries = gdt["entries"]
    let i = 0
    for i in range(len(entries)):
        let entry = entries[i]
        let j = 0
        for j in range(len(entry)):
            push(bytes, entry[j])
        end
    end
    return bytes
end

# --- GDTR structure (6 bytes: 2 limit + 4 base for 32-bit, or 10 bytes for 64-bit) ---
proc gdtr(base_addr, limit):
    let result = []
    # Limit: 16-bit value (size of GDT - 1)
    push_u16(result, limit)
    # Base: for 32-bit protected mode, 4 bytes
    push_u32(result, base_addr)
    return result
end

# --- GDTR for 64-bit mode (10 bytes: 2 limit + 8 base) ---
proc gdtr64(base_addr, limit):
    let result = []
    push_u16(result, limit)
    # 8-byte base address (low 4 bytes, high 4 bytes)
    push_u32(result, base_addr % 4294967296)
    let hi = (base_addr - (base_addr % 4294967296)) / 4294967296
    push_u32(result, hi)
    return result
end

# --- Get selector offset for an entry index ---
proc selector(index, rpl):
    return index * 8 + rpl
end

# --- Add a TSS to an existing GDT ---
proc add_tss(gdt, base, limit):
    let tss = tss_entry(base, limit)
    # TSS is 16 bytes, occupies 2 GDT slots
    push(gdt["entries"], tss)
    let idx = len(gdt["entries"]) - 1
    gdt["tss_sel"] = idx * 8
    return gdt
end

# --- Validate a GDT entry ---
proc validate_entry(entry):
    if len(entry) < 8:
        return false
    end
    # Check present bit in access byte (byte 5)
    let access = entry[5]
    let present = access / 128
    if present < 1:
        return false
    end
    return true
end

# --- Get entry count ---
proc entry_count(gdt):
    return len(gdt["entries"])
end

# --- Compute GDT limit (size - 1) ---
proc gdt_limit(gdt):
    let bytes = serialize(gdt)
    return len(bytes) - 1
end
