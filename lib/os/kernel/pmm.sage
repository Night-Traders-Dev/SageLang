gc_disable()

# pmm.sage — Physical Memory Manager
# Bitmap-based allocator, 1 bit per 4KB page.

# ----- Constants -----
let PAGE_SIZE = 4096

# ----- Internal state -----
let bitmap = []
let bitmap_size = 0
let total_pages = 0
let used_pages = 0
let memory_total = 0
let pmm_ready = false

# ----- Alignment helpers -----

proc align_up(addr, alignment):
    let remainder = addr % alignment
    if remainder == 0:
        return addr
    end
    return addr + (alignment - remainder)
end

proc align_down(addr, alignment):
    return addr - (addr % alignment)
end

# ----- Bitmap helpers -----

proc bit_index(page_num):
    return page_num / 32
end

proc bit_offset(page_num):
    return page_num % 32
end

proc set_bit(page_num):
    let idx = bit_index(page_num)
    let off = bit_offset(page_num)
    if idx < bitmap_size:
        # Simulate setting a bit by using a power-of-two flag array
        # In a real kernel this would be bitwise OR on a u32.
        let entry = bitmap[idx]
        let flags = entry["flags"]
        if dict_has(flags, str(off)) == false:
            flags[str(off)] = true
            used_pages = used_pages + 1
        end
    end
end

proc clear_bit(page_num):
    let idx = bit_index(page_num)
    let off = bit_offset(page_num)
    if idx < bitmap_size:
        let entry = bitmap[idx]
        let flags = entry["flags"]
        if dict_has(flags, str(off)):
            del flags[str(off)]
            used_pages = used_pages - 1
        end
    end
end

proc test_bit(page_num):
    let idx = bit_index(page_num)
    let off = bit_offset(page_num)
    if idx >= bitmap_size:
        return true
    end
    let entry = bitmap[idx]
    let flags = entry["flags"]
    if dict_has(flags, str(off)):
        return true
    end
    return false
end

# ----- Initialize from memory map -----

proc init(memory_map):
    # Default: 16 MB if no map provided
    memory_total = 16 * 1024 * 1024
    if memory_map != nil:
        if len(memory_map) > 0:
            # Find the highest usable address
            let highest = 0
            let i = 0
            while i < len(memory_map):
                let region = memory_map[i]
                let region_end = region["base"] + region["length"]
                if region_end > highest:
                    highest = region_end
                end
                i = i + 1
            end
            if highest > 0:
                memory_total = highest
            end
        end
    end

    total_pages = memory_total / PAGE_SIZE
    used_pages = 0
    bitmap_size = (total_pages / 32) + 1

    # Initialize bitmap — all pages marked free (no bits set)
    bitmap = []
    let i = 0
    while i < bitmap_size:
        let entry = {}
        let flags = {}
        entry["flags"] = flags
        append(bitmap, entry)
        i = i + 1
    end

    # Mark non-usable regions from the memory map as used
    if memory_map != nil:
        let m = 0
        while m < len(memory_map):
            let region = memory_map[m]
            if dict_has(region, "type"):
                if region["type"] != "available":
                    mark_region(region["base"], region["base"] + region["length"], true)
                end
            end
            m = m + 1
        end
    end

    pmm_ready = true
end

# ----- Mark a region as used or free -----

proc mark_region(start, end_addr, used):
    let page_start = align_up(start, PAGE_SIZE) / PAGE_SIZE
    let page_end = align_down(end_addr, PAGE_SIZE) / PAGE_SIZE
    let p = page_start
    while p < page_end:
        if p < total_pages:
            if used:
                set_bit(p)
            end
            if used == false:
                clear_bit(p)
            end
        end
        p = p + 1
    end
end

# ----- Allocate a single 4KB page -----

proc alloc_page():
    let p = 0
    while p < total_pages:
        if test_bit(p) == false:
            set_bit(p)
            return p * PAGE_SIZE
        end
        p = p + 1
    end
    return nil
end

# ----- Free a single page -----

proc free_page(addr):
    let page_num = addr / PAGE_SIZE
    if page_num < total_pages:
        clear_bit(page_num)
    end
end

# ----- Allocate contiguous pages -----

proc alloc_pages(count):
    if count < 1:
        return nil
    end
    let p = 0
    while p <= total_pages - count:
        let found = true
        let c = 0
        while c < count:
            if test_bit(p + c):
                found = false
                break
            end
            c = c + 1
        end
        if found:
            let c2 = 0
            while c2 < count:
                set_bit(p + c2)
                c2 = c2 + 1
            end
            return p * PAGE_SIZE
        end
        p = p + 1
    end
    return nil
end

# ----- Free contiguous pages -----

proc free_pages(addr, count):
    let page_num = addr / PAGE_SIZE
    let c = 0
    while c < count:
        if page_num + c < total_pages:
            clear_bit(page_num + c)
        end
        c = c + 1
    end
end

# ----- Statistics -----

proc total_memory():
    return memory_total
end

proc used_memory():
    return used_pages * PAGE_SIZE
end

proc free_memory():
    return (total_pages - used_pages) * PAGE_SIZE
end

proc stats():
    let s = {}
    s["total_bytes"] = memory_total
    s["total_pages"] = total_pages
    s["used_pages"] = used_pages
    s["free_pages"] = total_pages - used_pages
    s["used_bytes"] = used_memory()
    s["free_bytes"] = free_memory()
    s["page_size"] = PAGE_SIZE
    return s
end
