## os.boot.page_tables — PML4/PDPT/PD Builder for Bootloader Use
## Construct x86-64 page tables for the bootstrap environment.

let PRESENT        = 1
let WRITE          = 2
let USER           = 4
let PWT            = 8
let PCD            = 16
let ACCESSED       = 32
let DIRTY          = 64
let HUGE           = 128
let GLOBAL         = 256

## Build a bootstrap page table mapping:
## 1. Identity map [0, 4GB)
## 2. Higher-half kernel map
proc build_bootstrap(phys_base, kernel_virt, kernel_phys, kernel_size):
    let tables = {
        "phys_base": phys_base,
        "pml4": array_repeat(0, 512),
        "pdpt": array_repeat(0, 512),
        "pd":   array_repeat(0, 512)
    }
    
    # Simple implementation: 1 PML4 entry -> 1 PDPT entry -> 512 PD entries (2MB pages)
    # This covers 1GB per PDPT entry.
    # For identity 4GB, we need 4 PDPT entries and 4 PDs.
    
    # PML4[0] -> PDPT
    let pdpt_phys = phys_base + 4096
    tables["pml4"][0] = pdpt_phys | PRESENT | WRITE
    
    # Higher half kernel
    let pml4_idx = (kernel_virt >> 39) & 0x1FF
    tables["pml4"][pml4_idx] = (pdpt_phys + 4096) | PRESENT | WRITE # Another PDPT for kernel
    
    # ... more complex mapping logic ...
    
    return tables
end

## Map a range of memory in the provided tables
proc map_range(tables, virt, phys, size, flags):
    # Logic to walk levels and add entries
    return nil
end

## Serialize the tables to a byte array for writing to physical memory
proc serialize(tables):
    let bytes = []
    # PML4 (4KB)
    for entry in tables["pml4"]:
        let lo = entry & 0xFFFFFFFF
        let hi = (entry >> 32) & 0xFFFFFFFF
        push_u32_le(bytes, lo)
        push_u32_le(bytes, hi)
    end
    # PDPTs, PDs...
    return bytes
end

proc push_u32_le(arr, val):
    push(arr, val & 0xFF)
    push(arr, (val >> 8) & 0xFF)
    push(arr, (val >> 16) & 0xFF)
    push(arr, (val >> 24) & 0xFF)
end
