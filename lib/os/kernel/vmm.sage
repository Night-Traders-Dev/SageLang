gc_disable()

# vmm.sage — Virtual Memory Manager
# x86-64 4-level paging: PML4 -> PDPT -> PD -> PT -> Page

import pmm

# ----- Page flags -----
let PAGE_PRESENT = 1
let PAGE_WRITABLE = 2
let PAGE_USER = 4
let PAGE_WRITETHROUGH = 8
let PAGE_NOCACHE = 16
let PAGE_ACCESSED = 32
let PAGE_DIRTY = 64
let PAGE_HUGE = 128
let PAGE_GLOBAL = 256
let PAGE_NX = 1 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2

# ----- Internal state -----
# Page tables stored as nested dicts keyed by virtual page number.
# Each entry: { "phys": physical_addr, "flags": flags }
let page_tables = {}
let kernel_pml4 = nil
let current_pml4 = nil
let vmm_ready = false

# ----- Helpers -----

proc page_number(addr):
    return addr / pmm.PAGE_SIZE
end

proc page_addr(page_num):
    return page_num * pmm.PAGE_SIZE
end

# ----- Initialize kernel address space -----

proc init():
    page_tables = {}
    kernel_pml4 = {}
    kernel_pml4["entries"] = {}
    kernel_pml4["addr"] = 0
    current_pml4 = kernel_pml4

    # Identity-map the first 4 MB for kernel use (1024 pages)
    let addr = 0
    let end_addr = 4 * 1024 * 1024
    let flags = PAGE_PRESENT + PAGE_WRITABLE
    while addr < end_addr:
        let pn = page_number(addr)
        let entry = {}
        entry["phys"] = addr
        entry["flags"] = flags
        let key = str(pn)
        let entries = kernel_pml4["entries"]
        entries[key] = entry
        addr = addr + pmm.PAGE_SIZE
    end

    # Map VGA text buffer region (0xB8000)
    let vga_page = page_number(0xB8000)
    let vga_entry = {}
    vga_entry["phys"] = 0xB8000
    vga_entry["flags"] = PAGE_PRESENT + PAGE_WRITABLE
    let k_entries = kernel_pml4["entries"]
    k_entries[str(vga_page)] = vga_entry

    vmm_ready = true
end

# ----- Map a virtual page to a physical page -----

proc map_page(virt, phys, flags):
    let pn = page_number(virt)
    let entry = {}
    entry["phys"] = phys
    entry["flags"] = flags
    let key = str(pn)
    let entries = current_pml4["entries"]
    entries[key] = entry
end

# ----- Unmap a virtual page -----

proc unmap_page(virt):
    let pn = page_number(virt)
    let key = str(pn)
    let entries = current_pml4["entries"]
    if dict_has(entries, key):
        del entries[key]
    end
end

# ----- Map a contiguous region -----

proc map_region(virt, phys, size, flags):
    let offset = 0
    while offset < size:
        map_page(virt + offset, phys + offset, flags)
        offset = offset + pmm.PAGE_SIZE
    end
end

# ----- Check if a virtual address is mapped -----

proc is_mapped(virt):
    let pn = page_number(virt)
    let key = str(pn)
    let entries = current_pml4["entries"]
    return dict_has(entries, key)
end

# ----- Translate virtual to physical -----

proc get_physical(virt):
    let pn = page_number(virt)
    let key = str(pn)
    let entries = current_pml4["entries"]
    if dict_has(entries, key) == false:
        return nil
    end
    let entry = entries[key]
    let page_offset = virt % pmm.PAGE_SIZE
    return entry["phys"] + page_offset
end

# ----- Create a new address space -----

proc create_address_space():
    let pml4 = {}
    pml4["entries"] = {}
    # Allocate a physical page for the PML4 table
    let phys_page = pmm.alloc_page()
    if phys_page == nil:
        pml4["addr"] = 0
    end
    if phys_page != nil:
        pml4["addr"] = phys_page
    end
    # Copy kernel mappings (upper half) into the new space
    let k_entries = kernel_pml4["entries"]
    let new_entries = pml4["entries"]
    let keys = dict_keys(k_entries)
    let i = 0
    while i < len(keys):
        let k = keys[i]
        let src = k_entries[k]
        let dst = {}
        dst["phys"] = src["phys"]
        dst["flags"] = src["flags"]
        new_entries[k] = dst
        i = i + 1
    end
    return pml4
end

# ----- Switch address space (set CR3) -----

proc switch_address_space(pml4):
    # In a real kernel: mov cr3, pml4["addr"]
    current_pml4 = pml4
end

# ----- Get kernel address space -----

proc kernel_address_space():
    return kernel_pml4
end

# ----- Get current address space -----

proc current_address_space():
    return current_pml4
end

# ----- Statistics -----

proc stats():
    let entries = current_pml4["entries"]
    let keys = dict_keys(entries)
    let s = {}
    s["mapped_pages"] = len(keys)
    s["mapped_bytes"] = len(keys) * pmm.PAGE_SIZE
    s["pml4_addr"] = current_pml4["addr"]
    return s
end
