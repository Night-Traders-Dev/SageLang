# Test memory builtins in C backend
let buf = mem_alloc(64)
mem_write(buf, 0, "int", 42)
mem_write(buf, 8, "double", 3.14)
print mem_read(buf, 0, "int")
print mem_read(buf, 8, "double")
print mem_size(buf)
mem_free(buf)
