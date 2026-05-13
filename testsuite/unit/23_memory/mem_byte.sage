# Test byte read/write
# EXPECT: 0
# EXPECT: 42
# EXPECT: 255
# EXPECT: 0

let ptr = mem_alloc(16)

# Freshly allocated memory is zero
print mem_read(ptr, 0, "byte")

# Write and read back
mem_write(ptr, 0, "byte", 42)
print mem_read(ptr, 0, "byte")

# Max byte value
mem_write(ptr, 1, "byte", 255)
print mem_read(ptr, 1, "byte")

# Different offset doesn't affect first byte
print mem_read(ptr, 2, "byte")

mem_free(ptr)
