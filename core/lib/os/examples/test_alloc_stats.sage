import os.alloc
import assert

proc test_bump_stats():
    let b = alloc.bump_create(1024, 1024)
    let s1 = alloc.stats(b)
    assert.assert_equal(s1["bytes_used"], 0, "bump used 0")
    assert.assert_equal(s1["bytes_free"], 1024, "bump free 1024")
    assert.assert_equal(s1["num_allocs"], 0, "bump count 0")

    alloc.bump_alloc(b, 128, 4)
    let s2 = alloc.stats(b)
    assert.assert_equal(s2["bytes_used"], 128, "bump used 128")
    assert.assert_equal(s2["bytes_free"], 896, "bump free 896")
    assert.assert_equal(s2["num_allocs"], 1, "bump count 1")
    print "test_bump_stats passed"

proc test_freelist_stats():
    let f = alloc.freelist_create(2048, 1024)
    let s1 = alloc.stats(f)
    assert.assert_equal(s1["bytes_used"], 0, "flist used 0")
    assert.assert_equal(s1["bytes_free"], 1024, "flist free 1024")
    assert.assert_equal(s1["num_allocs"], 0, "flist count 0")

    let addr = alloc.freelist_alloc(f, 256, 4)
    let s2 = alloc.stats(f)
    assert.assert_equal(s2["bytes_used"], 256, "flist used 256")
    assert.assert_equal(s2["bytes_free"], 768, "flist free 768")
    assert.assert_equal(s2["num_allocs"], 1, "flist count 1")

    alloc.freelist_free(f, addr, 256)
    let s3 = alloc.stats(f)
    assert.assert_equal(s3["bytes_used"], 0, "flist used 0 after free")
    assert.assert_equal(s3["bytes_free"], 1024, "flist free 1024 after free")
    assert.assert_equal(s3["num_allocs"], 0, "flist count 0 after free")
    print "test_freelist_stats passed"

proc test_bitmap_stats():
    let m = alloc.bitmap_create(4096, 10, 4096)
    let s1 = alloc.stats(m)
    assert.assert_equal(s1["bytes_used"], 0, "bitmap used 0")
    assert.assert_equal(s1["bytes_free"], 40960, "bitmap free 40960")
    assert.assert_equal(s1["num_allocs"], 0, "bitmap count 0")

    alloc.alloc_page(m)
    let s2 = alloc.stats(m)
    assert.assert_equal(s2["bytes_used"], 4096, "bitmap used 4096")
    assert.assert_equal(s2["bytes_free"], 36864, "bitmap free 36864")
    assert.assert_equal(s2["num_allocs"], 1, "bitmap count 1")
    print "test_bitmap_stats passed"

test_bump_stats()
test_freelist_stats()
test_bitmap_stats()
print "All alloc stats tests passed!"
