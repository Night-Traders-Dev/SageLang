# Test int and double read/write
# EXPECT: 12345
# EXPECT: -99
# EXPECT: 3.14159

let ptr = mem_alloc(32)

# Write and read int
mem_write(ptr, 0, "int", 12345)
print mem_read(ptr, 0, "int")

# Negative int
mem_write(ptr, 4, "int", -99)
print mem_read(ptr, 4, "int")

# Write and read double
mem_write(ptr, 8, "double", 3.14159)
print mem_read(ptr, 8, "double")

mem_free(ptr)
