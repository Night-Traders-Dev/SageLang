# Kernel memory allocator
# Provides bump, free-list, and bitmap allocators for kernel heap/page management
# All allocators work on abstract address ranges (no hardware dependency)

# Allocator type constants
let ALLOC_BUMP = 1
let ALLOC_FREELIST = 2
let ALLOC_BITMAP = 3

# ============================================================================
# Bump Allocator (fast, no free)
# ============================================================================

# Create a bump allocator over an address range
proc bump_create(base, size):
    let alloc = {}
    alloc["type"] = 1
    alloc["base"] = base
    alloc["size"] = size
    alloc["next"] = base
    alloc["end"] = base + size
    alloc["count"] = 0
    return alloc

# Allocate n bytes from bump allocator (returns address or -1)
proc bump_alloc(alloc, size, alignment):
    # Align up
    let addr = alloc["next"]
    let mask = alignment - 1
    let aligned = (addr + mask) & (0 - alignment)
    if aligned + size > alloc["end"]:
        return -1
    alloc["next"] = aligned + size
    alloc["count"] = alloc["count"] + 1
    return aligned

# Reset bump allocator (free everything at once)
proc bump_reset(alloc):
    alloc["next"] = alloc["base"]
    alloc["count"] = 0

# Get remaining space
proc bump_remaining(alloc):
    return alloc["end"] - alloc["next"]

# Get total allocated
proc bump_used(alloc):
    return alloc["next"] - alloc["base"]

# ============================================================================
# Free-List Allocator (supports individual free)
# ============================================================================

# Create a free-list allocator
proc freelist_create(base, size):
    let alloc = {}
    alloc["type"] = 2
    alloc["base"] = base
    alloc["size"] = size
    # Free list: array of {addr, size} entries, sorted by address
    let initial = {}
    initial["addr"] = base
    initial["size"] = size
    alloc["free_list"] = [initial]
    alloc["alloc_count"] = 0
    alloc["free_count"] = 1
    alloc["used"] = 0
    return alloc

# Find first fit block in free list
proc freelist_alloc(alloc, size, alignment):
    let flist = alloc["free_list"]
    for i in range(len(flist)):
        let block = flist[i]
        let addr = block["addr"]
        let mask = alignment - 1
        let aligned = (addr + mask) & (0 - alignment)
        let waste = aligned - addr
        if block["size"] >= size + waste:
            # Found a fit
            let result = aligned
            if block["size"] == size + waste:
                # Exact fit: remove block
                let new_list = []
                for j in range(len(flist)):
                    if j != i:
                        push(new_list, flist[j])
                alloc["free_list"] = new_list
                alloc["free_count"] = alloc["free_count"] - 1
            else:
                # Split block
                block["addr"] = aligned + size
                block["size"] = block["size"] - size - waste
            alloc["alloc_count"] = alloc["alloc_count"] + 1
            alloc["used"] = alloc["used"] + size
            return result
    return -1

# Free a block back to the free list
proc freelist_free(alloc, addr, size):
    let flist = alloc["free_list"]
    # Insert in sorted order
    let new_block = {}
    new_block["addr"] = addr
    new_block["size"] = size
    let inserted = false
    let new_list = []
    for i in range(len(flist)):
        if not inserted and flist[i]["addr"] > addr:
            push(new_list, new_block)
            inserted = true
        push(new_list, flist[i])
    if not inserted:
        push(new_list, new_block)
    # Coalesce adjacent blocks
    let coalesced = []
    let current = new_list[0]
    for i in range(len(new_list) - 1):
        let next = new_list[i + 1]
        if current["addr"] + current["size"] == next["addr"]:
            current["size"] = current["size"] + next["size"]
        else:
            push(coalesced, current)
            current = next
    push(coalesced, current)
    alloc["free_list"] = coalesced
    alloc["free_count"] = len(coalesced)
    alloc["alloc_count"] = alloc["alloc_count"] - 1
    alloc["used"] = alloc["used"] - size

# Get fragmentation info
proc freelist_stats(alloc):
    let stats = {}
    stats["total"] = alloc["size"]
    stats["used"] = alloc["used"]
    stats["free"] = alloc["size"] - alloc["used"]
    stats["fragments"] = len(alloc["free_list"])
    stats["alloc_count"] = alloc["alloc_count"]
    # Largest free block
    let largest = 0
    let flist = alloc["free_list"]
    for i in range(len(flist)):
        if flist[i]["size"] > largest:
            largest = flist[i]["size"]
    stats["largest_free"] = largest
    return stats

# ============================================================================
# Bitmap Page Allocator (for physical page frames)
# ============================================================================

# Create a bitmap page allocator
# base: start of managed physical memory
# num_pages: number of pages to manage
# page_size: size of each page (typically 4096)
proc bitmap_create(base, num_pages, page_size):
    let alloc = {}
    alloc["type"] = 3
    alloc["base"] = base
    alloc["num_pages"] = num_pages
    alloc["page_size"] = page_size
    # Bitmap: array of 0/1 values (0 = free, 1 = used)
    let bitmap = []
    for i in range(num_pages):
        push(bitmap, 0)
    alloc["bitmap"] = bitmap
    alloc["used_count"] = 0
    return alloc

# Allocate a single page (returns page address or -1)
proc bitmap_alloc_page(alloc):
    let bitmap = alloc["bitmap"]
    let num = alloc["num_pages"]
    for i in range(num):
        if bitmap[i] == 0:
            bitmap[i] = 1
            alloc["used_count"] = alloc["used_count"] + 1
            return alloc["base"] + i * alloc["page_size"]
    return -1

# Free a single page
proc bitmap_free_page(alloc, addr):
    let idx = ((addr - alloc["base"]) / alloc["page_size"]) | 0
    if idx >= 0 and idx < alloc["num_pages"]:
        if alloc["bitmap"][idx] == 1:
            alloc["bitmap"][idx] = 0
            alloc["used_count"] = alloc["used_count"] - 1
            return true
    return false

# Allocate n contiguous pages (returns base address or -1)
proc bitmap_alloc_pages(alloc, count):
    let bitmap = alloc["bitmap"]
    let num = alloc["num_pages"]
    let i = 0
    while i + count <= num:
        let found = true
        for j in range(count):
            if bitmap[i + j] != 0:
                found = false
                i = i + j + 1
                j = count
        if found:
            for j in range(count):
                bitmap[i + j] = 1
            alloc["used_count"] = alloc["used_count"] + count
            return alloc["base"] + i * alloc["page_size"]
        if found:
            i = num
    return -1

# Free n contiguous pages
proc bitmap_free_pages(alloc, addr, count):
    let idx = ((addr - alloc["base"]) / alloc["page_size"]) | 0
    for i in range(count):
        if idx + i < alloc["num_pages"]:
            if alloc["bitmap"][idx + i] == 1:
                alloc["bitmap"][idx + i] = 0
                alloc["used_count"] = alloc["used_count"] - 1

# Mark a range of pages as used (e.g., kernel image, reserved regions)
proc bitmap_mark_used(alloc, addr, size):
    let page_size = alloc["page_size"]
    let start_page = ((addr - alloc["base"]) / page_size) | 0
    let num = ((size + page_size - 1) / page_size) | 0
    for i in range(num):
        let idx = start_page + i
        if idx >= 0 and idx < alloc["num_pages"]:
            if alloc["bitmap"][idx] == 0:
                alloc["bitmap"][idx] = 1
                alloc["used_count"] = alloc["used_count"] + 1

# Get allocator statistics
proc bitmap_stats(alloc):
    let stats = {}
    stats["total_pages"] = alloc["num_pages"]
    stats["used_pages"] = alloc["used_count"]
    stats["free_pages"] = alloc["num_pages"] - alloc["used_count"]
    stats["total_bytes"] = alloc["num_pages"] * alloc["page_size"]
    stats["used_bytes"] = alloc["used_count"] * alloc["page_size"]
    stats["free_bytes"] = (alloc["num_pages"] - alloc["used_count"]) * alloc["page_size"]
    return stats

# Check if an address is within the allocator's range
proc bitmap_contains(alloc, addr):
    let end_addr = alloc["base"] + alloc["num_pages"] * alloc["page_size"]
    return addr >= alloc["base"] and addr < end_addr

# Check if a specific page is allocated
proc bitmap_is_used(alloc, addr):
    let idx = ((addr - alloc["base"]) / alloc["page_size"]) | 0
    if idx < 0 or idx >= alloc["num_pages"]:
        return false
    return alloc["bitmap"][idx] == 1
