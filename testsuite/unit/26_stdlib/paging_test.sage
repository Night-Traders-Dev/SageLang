gc_disable()
# EXPECT: 0
# EXPECT: 0
# EXPECT: 0
# EXPECT: 1
# EXPECT: 0
# EXPECT: true
# EXPECT: true
# EXPECT: false
# EXPECT: 4096
# EXPECT: 8192
# EXPECT: 2
# EXPECT: PML4

import os.paging

# Test page index extraction for address 0x1000 (4096)
print paging.page_index(4096, 4)
print paging.page_index(4096, 3)
print paging.page_index(4096, 2)
print paging.page_index(4096, 1)
print paging.page_offset_4k(4096)

# Test PTE decode
let entry = paging.make_pte(4096, 3)
let decoded = paging.decode_pte(entry)
print decoded["present"]
print decoded["writable"]
print decoded["user"]
print decoded["address"]

# Test alignment
print paging.align_up(5000, 4096)

# Test pages_needed
print paging.pages_needed(4097, 4096)

# Test level name
print paging.level_name(4)
