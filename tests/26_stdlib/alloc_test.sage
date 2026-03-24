gc_disable()
# EXPECT: 4096
# EXPECT: 0
# EXPECT: 4096
# EXPECT: 8192
# EXPECT: 2
# EXPECT: 0
# EXPECT: 4096
# EXPECT: true
# EXPECT: 8

import os.alloc

# Bump allocator
let bump = alloc.bump_create(4096, 65536)
let a1 = alloc.bump_alloc(bump, 100, 1)
print a1
alloc.bump_reset(bump)
print alloc.bump_used(bump)

# Free-list allocator
let fl = alloc.freelist_create(4096, 65536)
let b1 = alloc.freelist_alloc(fl, 4096, 4096)
print b1
let b2 = alloc.freelist_alloc(fl, 4096, 4096)
print b2
alloc.freelist_free(fl, b1, 4096)
let stats = alloc.freelist_stats(fl)
print stats["fragments"]

# Bitmap page allocator
let bm = alloc.bitmap_create(0, 10, 4096)
let p1 = alloc.bitmap_alloc_page(bm)
print p1
let p2 = alloc.bitmap_alloc_page(bm)
print p2
print alloc.bitmap_is_used(bm, 0)
let bstats = alloc.bitmap_stats(bm)
print bstats["free_pages"]
