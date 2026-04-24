gc_disable()

# vmm.sage — Virtual Memory Manager
# x86-64 4-level paging: PML4 -> PDPT -> PD -> PT -> Page

import os.kernel.pmm as pmm
let PAGE_SIZE = 4096

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
    return addr / PAGE_SIZE
end

proc page_addr(page_num):
    return page_num * PAGE_SIZE
end

# ----- Initialize kernel address space -----

proc init():
    let state = vmm_init("x86_64")
    page_tables = state["entries"]
    kernel_pml4 = {}
    kernel_pml4["entries"] = state["entries"]
    kernel_pml4["addr"] = 0
    current_pml4 = kernel_pml4
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
        dict_delete(entries, key)
    end
end

# ----- Map a contiguous region -----

proc map_region(virt, phys, size, flags):
    let offset = 0
    while offset < size:
        map_page(virt + offset, phys + offset, flags)
        offset = offset + PAGE_SIZE
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
    let page_offset = virt % PAGE_SIZE
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
    s["mapped_bytes"] = len(keys) * PAGE_SIZE
    s["pml4_addr"] = current_pml4["addr"]
    return s
end

# =========================================================================
# Architecture-Aware VMM Interface
# =========================================================================
# Supports "x86_64", "aarch64", and "riscv64".
# The existing x86_64 functions above remain untouched; these new
# functions dispatch per-architecture using a state dict.

# ----- AArch64 page flags -----
let AARCH64_PAGE_VALID = 1
let AARCH64_PAGE_TABLE = 2
let AARCH64_PAGE_AF    = 1024
let AARCH64_PAGE_AP_RW = 64

# ----- RISC-V 64 page flags -----
let RV64_PAGE_V = 1
let RV64_PAGE_R = 2
let RV64_PAGE_W = 4
let RV64_PAGE_X = 8
let RV64_PAGE_U = 16

# ----- Create an arch-specific VMM state -----

proc vmm_init(arch):
    let state = {}
    state["arch"] = arch
    state["entries"] = {}
    state["ready"] = false

    if arch == "x86_64":
        # Identity-map first 4 MB (1024 pages)
        let addr = 0
        let end_addr = 4 * 1024 * 1024
        let flags = PAGE_PRESENT + PAGE_WRITABLE
        let entries = state["entries"]
        while addr < end_addr:
            let pn = page_number(addr)
            let entry = {}
            entry["phys"] = addr
            entry["flags"] = flags
            entries[str(pn)] = entry
            addr = addr + PAGE_SIZE
        end
        # Map VGA text buffer
        let vga_pn = page_number(753664)
        let vga_entry = {}
        vga_entry["phys"] = 753664
        vga_entry["flags"] = PAGE_PRESENT + PAGE_WRITABLE
        entries[str(vga_pn)] = vga_entry
    end

    if arch == "aarch64":
        # Identity-map first 4 MB with valid + table + AF + AP_RW
        let addr = 0
        let end_addr = 4 * 1024 * 1024
        let flags = AARCH64_PAGE_VALID + AARCH64_PAGE_TABLE + AARCH64_PAGE_AF + AARCH64_PAGE_AP_RW
        let entries = state["entries"]
        while addr < end_addr:
            let pn = page_number(addr)
            let entry = {}
            entry["phys"] = addr
            entry["flags"] = flags
            let key = str(pn)
            entries[key] = entry
            page_tables[key] = entry
            addr = addr + PAGE_SIZE
        end
    end

    if arch == "riscv64":
        # Identity-map first 4 MB with V + R + W
        let addr = 0
        let end_addr = 4 * 1024 * 1024
        let flags = RV64_PAGE_V + RV64_PAGE_R + RV64_PAGE_W
        let entries = state["entries"]
        while addr < end_addr:
            let pn = page_number(addr)
            let entry = {}
            entry["phys"] = addr
            entry["flags"] = flags
            let key = str(pn)
            entries[key] = entry
            page_tables[key] = entry
            addr = addr + PAGE_SIZE
        end
    end

    state["ready"] = true
    return state
end

# ----- Map a virtual page in an arch-aware VMM state -----

proc vmm_map(state, vaddr, paddr, flags):
    let arch = state["arch"]
    let pn = page_number(vaddr)
    let key = str(pn)
    let entry = {}
    entry["phys"] = paddr
    entry["flags"] = flags

    if arch == "x86_64":
        let entries = state["entries"]
        entries[key] = entry
    end
    if arch == "aarch64":
        let entries = state["entries"]
        entries[key] = entry
    end
    if arch == "riscv64":
        let entries = state["entries"]
        entries[key] = entry
    end
end

# ----- Unmap a virtual page in an arch-aware VMM state -----

proc vmm_unmap(state, vaddr):
    let arch = state["arch"]
    let pn = page_number(vaddr)
    let key = str(pn)

    if arch == "x86_64":
        let entries = state["entries"]
        if dict_has(entries, key):
            dict_delete(entries, key)
        end
    end
    if arch == "aarch64":
        let entries = state["entries"]
        if dict_has(entries, key):
            dict_delete(entries, key)
        end
    end
    if arch == "riscv64":
        let entries = state["entries"]
        if dict_has(entries, key):
            dict_delete(entries, key)
        end
    end
end
