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
    if level == 3:
        return "PDPT"
    if level == 2:
        return "PD"
    if level == 1:
        return "PT"
    return "Unknown"

# Extract page table index from virtual address at a given level
proc page_index(vaddr, level):
    if level == 4:
        return (vaddr >> 39) & 511
    if level == 3:
        return (vaddr >> 30) & 511
    if level == 2:
        return (vaddr >> 21) & 511
    if level == 1:
        return (vaddr >> 12) & 511
    return 0

# Extract page offset from virtual address
proc page_offset_4k(vaddr):
    return vaddr & 4095

proc page_offset_2m(vaddr):
    return vaddr & 2097151

proc page_offset_1g(vaddr):
    return vaddr & 1073741823

# Align address down to page boundary
proc align_down(addr, alignment):
    return addr - (addr & (alignment - 1))

# Align address up to page boundary
proc align_up(addr, alignment):
    let mask = alignment - 1
    return (addr + mask) - ((addr + mask) & mask)

# Calculate number of pages needed for a given size
proc pages_needed(size, page_size):
    return ((size + page_size - 1) / page_size) | 0

# Create a page table entry
proc make_pte(phys_addr, flags):
    return (phys_addr & 4503599627366400) + (flags & 4095)

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
    return mappings

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
    return mappings

# Describe a virtual address in terms of page table indices
proc describe_vaddr(vaddr):
    let desc = {}
    desc["pml4_index"] = page_index(vaddr, 4)
    desc["pdpt_index"] = page_index(vaddr, 3)
    desc["pd_index"] = page_index(vaddr, 2)
    desc["pt_index"] = page_index(vaddr, 1)
    desc["offset"] = page_offset_4k(vaddr)
    return desc

# Check if an address is canonical (x86-64)
proc is_canonical(vaddr):
    let top_bits = (vaddr >> 47) & 131071
    return top_bits == 0 or top_bits == 131071

# Get the higher-half kernel base address (conventional -2GB)
proc kernel_base():
    # 0xFFFFFFFF80000000 = 18446744071562067968
    return 18446744071562067968

# Get the higher-half direct map base (Linux convention at 0xFFFF888000000000)
proc direct_map_base():
    return 18446612682702848000
