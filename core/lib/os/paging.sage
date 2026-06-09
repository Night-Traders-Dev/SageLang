# x86-64 page table structures and utilities
# Provides helpers for building and inspecting 4-level page tables

# Page sizes
let PAGE_SIZE_4K = 4096
let PAGE_SIZE_2M = 2097152
let PAGE_SIZE_1G = 1073741824

# Page table entry flags (x86-64)
let PTE_PRESENT = 1
let PTE_WRITABLE = 2
let PTE_USER = 4
let PTE_WRITE_THROUGH = 8
let PTE_CACHE_DISABLE = 16
let PTE_ACCESSED = 32
let PTE_DIRTY = 64
let PTE_HUGE = 128
let PTE_GLOBAL = 256
let PTE_NO_EXECUTE = 9223372036854775808

# Common page flag combinations
let PAGE_RO = 1
let PAGE_RW = 3
let PAGE_USER_RO = 5
let PAGE_USER_RW = 7
let PAGE_KERNEL_CODE = 1
let PAGE_KERNEL_DATA = 3
let PAGE_MMIO = 19

# Page table level names
proc level_name(level):
    if level == 4:
        return "PML4"
    end
    if level == 3:
        return "PDPT"
    end
    if level == 2:
        return "PD"
    end
    if level == 1:
        return "PT"
    end
    return "Unknown"
end

# Extract page table index from virtual address at a given level
proc page_index(vaddr, level):
    if level == 4:
        return (vaddr >> 39) & 511
    end
    if level == 3:
        return (vaddr >> 30) & 511
    end
    if level == 2:
        return (vaddr >> 21) & 511
    end
    if level == 1:
        return (vaddr >> 12) & 511
    end
    return 0
end

# Extract page offset from virtual address
proc page_offset_4k(vaddr):
    return vaddr & 4095
end

proc page_offset_2m(vaddr):
    return vaddr & 2097151
end

proc page_offset_1g(vaddr):
    return vaddr & 1073741823
end

# Align address down to page boundary
proc align_down(addr, alignment):
    return addr - (addr & (alignment - 1))
end

# Align address up to page boundary
proc align_up(addr, alignment):
    let mask = alignment - 1
    return (addr + mask) - ((addr + mask) & mask)
end

# Calculate number of pages needed for a given size
proc pages_needed(size, page_size):
    return ((size + page_size - 1) / page_size) | 0
end

# Create a page table entry
proc make_pte(phys_addr, flags):
    return (phys_addr & 4503599627366400) + (flags & 4095)
end

# Decode a page table entry
proc decode_pte(entry):
    let pte = {}
    pte["raw"] = entry
    pte["present"] = (entry & 1) != 0
    pte["writable"] = (entry & 2) != 0
    pte["user"] = (entry & 4) != 0
    pte["write_through"] = (entry & 8) != 0
    pte["cache_disable"] = (entry & 16) != 0
    pte["accessed"] = (entry & 32) != 0
    pte["dirty"] = (entry & 64) != 0
    pte["huge"] = (entry & 128) != 0
    pte["global"] = (entry & 256) != 0
    pte["address"] = entry & 4503599627366400
    return pte
end

# Create an identity-mapped page table layout (for bootloader/early kernel)
# Returns a list of mapping descriptors, not actual tables
proc identity_map_range(phys_start, phys_end, flags):
    let mappings = []
    let addr = align_down(phys_start, 4096)
    let end_addr = align_up(phys_end, 4096)
    while addr < end_addr:
        let m = {}
        m["vaddr"] = addr
        m["paddr"] = addr
        m["flags"] = flags
        m["size"] = 4096
        push(mappings, m)
        addr = addr + 4096
    end
    return mappings
end

# Create a higher-half kernel mapping layout
# Maps phys_start..phys_end to virt_base + (phys_start..phys_end)
proc higher_half_map(phys_start, phys_end, virt_base, flags):
    let mappings = []
    let addr = align_down(phys_start, 4096)
    let end_addr = align_up(phys_end, 4096)
    while addr < end_addr:
        let m = {}
        m["vaddr"] = virt_base + addr
        m["paddr"] = addr
        m["flags"] = flags
        m["size"] = 4096
        push(mappings, m)
        addr = addr + 4096
    end
    return mappings
end

# Describe a virtual address in terms of page table indices
proc describe_vaddr(vaddr):
    let desc = {}
    desc["pml4_index"] = page_index(vaddr, 4)
    desc["pdpt_index"] = page_index(vaddr, 3)
    desc["pd_index"] = page_index(vaddr, 2)
    desc["pt_index"] = page_index(vaddr, 1)
    desc["offset"] = page_offset_4k(vaddr)
    return desc
end

# Check if an address is canonical (x86-64)
proc is_canonical(vaddr):
    let top_bits = (vaddr >> 47) & 131071
    return top_bits == 0 or top_bits == 131071
end

# Get the higher-half kernel base address (conventional -2GB)
proc kernel_base():
    # 0xFFFFFFFF80000000 = 18446744071562067968
    return 18446744071562067968
end

# Get the higher-half direct map base (Linux convention at 0xFFFF888000000000)
proc direct_map_base():
    return 18446612682702848000
end

# =========================================================================
# AArch64 (ARMv8) Page Table Support — 4KB granule, 4-level (L0-L3)
# =========================================================================

# AArch64 PTE flag constants
let AARCH64_PTE_VALID  = 1       # bit 0: entry is valid
let AARCH64_PTE_TABLE  = 2       # bit 1: table descriptor (vs block)
let AARCH64_PTE_AF     = 1024    # bit 10: access flag
let AARCH64_PTE_AP_RW  = 64      # bit 6: AP[1] — read/write at EL1

# Address mask: bits 12-47 (physical address in a 4KB granule PTE)
# (2^48 - 1) - (2^12 - 1) = 281474976706560 - 4095 = 281474976706560 & ~4095
let AARCH64_ADDR_MASK = 281474976706560

# Create an AArch64 page table entry
# phys_addr occupies bits 12-47, flags occupy the attribute bits
proc aarch64_make_pte(phys_addr, flags):
    return (phys_addr & AARCH64_ADDR_MASK) + flags
end

# Decode an AArch64 page table entry into a dict
proc aarch64_decode_pte(entry):
    let pte = {}
    pte["raw"] = entry
    pte["valid"] = (entry & 1) != 0
    pte["table"] = (entry & 2) != 0
    pte["AP"] = (entry >> 6) & 3
    pte["AF"] = (entry & 1024) != 0
    pte["address"] = entry & AARCH64_ADDR_MASK
    return pte
end

# Describe an AArch64 virtual address by splitting into level indices
# 4KB granule, 48-bit VA: L0[47:39], L1[38:30], L2[29:21], L3[20:12], offset[11:0]
proc aarch64_describe_vaddr(addr):
    let desc = {}
    desc["L0_index"] = (addr >> 39) & 511
    desc["L1_index"] = (addr >> 30) & 511
    desc["L2_index"] = (addr >> 21) & 511
    desc["L3_index"] = (addr >> 12) & 511
    desc["offset"] = addr & 4095
    return desc
end

# =========================================================================
# RISC-V 64 (Sv48) Page Table Support — 4KB pages, 4-level
# =========================================================================

# RISC-V PTE flag constants (bits 0-4)
let RV64_PTE_V = 1     # bit 0: valid
let RV64_PTE_R = 2     # bit 1: readable
let RV64_PTE_W = 4     # bit 2: writable
let RV64_PTE_X = 8     # bit 3: executable
let RV64_PTE_U = 16    # bit 4: user-accessible

# PPN mask: bits 10-53 in an Sv48 PTE
# (2^54 - 1) - (2^10 - 1) = 18014398509481984 - 1023 = 18014398509481984 & ~1023
let RV64_PPN_MASK = 18014398509481984

# Create a RISC-V 64 Sv48 page table entry
# Physical page number is stored in bits 10-53; flags in bits 0-7
proc riscv64_make_pte(phys_addr, flags):
    let ppn = (phys_addr >> 12) << 10
    return (ppn & RV64_PPN_MASK) + (flags & 255)
end

# Decode a RISC-V 64 Sv48 page table entry into a dict
proc riscv64_decode_pte(entry):
    let pte = {}
    pte["raw"] = entry
    pte["V"] = (entry & 1) != 0
    pte["R"] = (entry & 2) != 0
    pte["W"] = (entry & 4) != 0
    pte["X"] = (entry & 8) != 0
    pte["U"] = (entry & 16) != 0
    pte["PPN"] = (entry & RV64_PPN_MASK) >> 10
    # Reconstruct the physical address from the PPN
    pte["address"] = ((entry & RV64_PPN_MASK) >> 10) << 12
    return pte
end

# Describe a RISC-V 64 Sv48 virtual address by splitting into VPN levels
# Sv48: VPN[3][47:39], VPN[2][38:30], VPN[1][29:21], VPN[0][20:12], offset[11:0]
proc riscv64_describe_vaddr(addr):
    let desc = {}
    desc["VPN3"] = (addr >> 39) & 511
    desc["VPN2"] = (addr >> 30) & 511
    desc["VPN1"] = (addr >> 21) & 511
    desc["VPN0"] = (addr >> 12) & 511
    desc["offset"] = addr & 4095
    return desc
end

# =========================================================================
# Architecture Dispatcher
# =========================================================================

# Dispatch make_pte by architecture name
# arch: "x86_64", "aarch64", or "riscv64"
proc arch_make_pte(arch, phys_addr, flags):
    if arch == "x86_64":
        return make_pte(phys_addr, flags)
    end
    if arch == "aarch64":
        return aarch64_make_pte(phys_addr, flags)
    end
    if arch == "riscv64":
        return riscv64_make_pte(phys_addr, flags)
    end
    return nil
end

# Dispatch decode_pte by architecture name
proc arch_decode_pte(arch, entry):
    if arch == "x86_64":
        return decode_pte(entry)
    end
    if arch == "aarch64":
        return aarch64_decode_pte(entry)
    end
    if arch == "riscv64":
        return riscv64_decode_pte(entry)
    end
    return nil
end

# Dispatch describe_vaddr by architecture name
proc arch_describe_vaddr(arch, addr):
    if arch == "x86_64":
        return describe_vaddr(addr)
    end
    if arch == "aarch64":
        return aarch64_describe_vaddr(addr)
    end
    if arch == "riscv64":
        return riscv64_describe_vaddr(addr)
    end
    return nil
end
