gc_disable()
# EXPECT: pmm_init
# EXPECT: page_allocated
# EXPECT: page_freed
# EXPECT: PASS
let PAGE_SIZE = 4096
let bitmap = []
for i in range(128):
    push(bitmap, 0)
let total_pages = 128
let used = 0
print "pmm_init"
bitmap[0] = 1
used = used + 1
if bitmap[0] == 1:
    print "page_allocated"
bitmap[0] = 0
used = used - 1
if bitmap[0] == 0 and used == 0:
    print "page_freed"
print "PASS"
