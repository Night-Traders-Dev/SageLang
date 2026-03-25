gc_disable()
# EXPECT: vmm_init
# EXPECT: page_mapped
# EXPECT: translation_works
# EXPECT: PASS

import os.kernel.pmm
import os.kernel.vmm

# Initialize PMM first (VMM depends on it)
let mem_map = []
let region = {}
region["base"] = 0
region["length"] = 16777216
region["type"] = "available"
push(mem_map, region)
pmm.init(mem_map)

# Initialize VMM
vmm.init()

let s = vmm.stats()
if s["mapped_pages"] > 0
    print "vmm_init"
end

# Map a custom page: virtual 0x400000 -> physical 0x200000
let virt = 4194304
let phys = 2097152
let flags = vmm.PAGE_PRESENT + vmm.PAGE_WRITABLE
vmm.map_page(virt, phys, flags)

if vmm.is_mapped(virt)
    print "page_mapped"
end

# Check translation
let translated = vmm.get_physical(virt)
if translated == phys
    print "translation_works"
end

print "PASS"
