# Test mem_alloc and mem_free
# EXPECT: 64
# EXPECT: done

let ptr = mem_alloc(64)
print mem_size(ptr)
mem_free(ptr)
print "done"
