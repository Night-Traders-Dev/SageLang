# Test using memory as a byte buffer
# EXPECT: 72
# EXPECT: 101
# EXPECT: 108
# EXPECT: 108
# EXPECT: 111

# Write "Hello" as bytes into a buffer
let buf = mem_alloc(16)
mem_write(buf, 0, "byte", 72)   # H
mem_write(buf, 1, "byte", 101)  # e
mem_write(buf, 2, "byte", 108)  # l
mem_write(buf, 3, "byte", 108)  # l
mem_write(buf, 4, "byte", 111)  # o

# Read back each byte
let i = 0
while i < 5:
    print mem_read(buf, i, "byte")
    i = i + 1

mem_free(buf)
