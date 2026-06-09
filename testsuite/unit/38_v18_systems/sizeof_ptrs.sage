# EXPECT: 8
# EXPECT: 4
# EXPECT: 42
# EXPECT: 20
# Test sizeof
print sizeof(3.14)
print sizeof("test")

# Test unsafe block + pointer ops
unsafe:
    let p = mem_alloc(16)
    mem_write(p, 0, "int", 42)
    print mem_read(p, 0, "int")
    mem_free(p)

# Test ptr_add
let p2 = mem_alloc(64)
mem_write(p2, 0, "int", 10)
mem_write(p2, 4, "int", 20)
let p3 = ptr_add(p2, 4)
print mem_read(p3, 0, "int")
mem_free(p2)
