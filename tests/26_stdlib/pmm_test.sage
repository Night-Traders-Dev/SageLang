gc_disable()
# EXPECT: pmm_init
# EXPECT: page_allocated
# EXPECT: page_freed
# EXPECT: stats_correct
# EXPECT: PASS

import os.kernel.pmm

# Create a fake memory map with one available region
let mem_map = []
let region = {}
region["base"] = 0x100000
region["length"] = 4194304
region["type"] = "available"
push(mem_map, region)

# Initialize PMM with fake memory map
pmm.init(mem_map)

let s = pmm.stats()
if s["total_pages"] > 0
    print "pmm_init"
end

# Allocate a page
let page = pmm.alloc_page()
if page != nil
    print "page_allocated"
end

# Free the page
let before_free = pmm.stats()
let used_before = before_free["used_pages"]
pmm.free_page(page)
let after_free = pmm.stats()
let used_after = after_free["used_pages"]
if used_after < used_before
    print "page_freed"
end

# Verify stats are consistent
let final_stats = pmm.stats()
if final_stats["page_size"] == 4096
    print "stats_correct"
end

print "PASS"
