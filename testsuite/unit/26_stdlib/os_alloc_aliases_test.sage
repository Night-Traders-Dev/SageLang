# EXPECT: bump_ok
# EXPECT: freelist_ok
# EXPECT: bitmap_ok
# EXPECT: aliases_ok
# EXPECT: PASS
import os.alloc as alloc

# Bump allocator
let bump = alloc.bump_create(0, 4096)
let b1 = alloc.bump_alloc(bump, 128, 16)
let b2 = alloc.bump_alloc(bump, 128, 16)
if b1 == 0 and b2 == 128:
    if alloc.bump_used(bump) == 256:
        if alloc.bump_remaining(bump) == 3840:
            alloc.bump_reset(bump)
            if alloc.bump_used(bump) == 0:
                print "bump_ok"
            end
        end
    end
end

# Free-list allocator
let fl = alloc.freelist_create(0, 4096)
let f1 = alloc.freelist_alloc(fl, 256, 16)
let f2 = alloc.freelist_alloc(fl, 256, 16)
if f1 == 0 and f2 == 256:
    alloc.freelist_free(fl, 0, 256)
    let st = alloc.freelist_stats(fl)
    if st["used"] == 256 and st["fragments"] >= 1:
        print "freelist_ok"
    end
end

# Bitmap allocator
let bm = alloc.bitmap_create(0, 8, 4096)
let pg1 = alloc.bitmap_alloc_page(bm)
let pg2 = alloc.bitmap_alloc_page(bm)
if pg1 == 0 and pg2 == 4096:
    let bst = alloc.bitmap_stats(bm)
    if bst["used_pages"] == 2 and bst["free_pages"] == 6:
        alloc.bitmap_free_page(bm, 0)
        let pg3 = alloc.bitmap_alloc_page(bm)
        if pg3 == 0:
            print "bitmap_ok"
        end
    end
end

# Aliases: free_page, alloc_page, free_pages, alloc_pages
let bm2 = alloc.bitmap_create(0, 8, 4096)
let ap = alloc.alloc_page(bm2)
if ap == 0:
    alloc.free_page(bm2, 0)
    let ap2 = alloc.alloc_page(bm2)
    if ap2 == 0:
        let aps = alloc.alloc_pages(bm2, 3)
        if aps == 4096:
            alloc.free_pages(bm2, 4096, 3)
            print "aliases_ok"
        end
    end
end

print "PASS"
