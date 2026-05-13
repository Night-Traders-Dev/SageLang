## Test: Kotlin backend — FFI and memory operations
## Run: sage --emit-kotlin tests/42_kotlin/emit_memory.sage

## Memory allocation and read/write
let buf = mem_alloc(256)
mem_write(buf, 0, "int", 42)
mem_write(buf, 4, "int", 100)
mem_write(buf, 8, "double", 3.14)

let a = mem_read(buf, 0, "int")
let b = mem_read(buf, 4, "int")
let c = mem_read(buf, 8, "double")

print(a)
print(b)
print(c)

mem_free(buf)

## Assembly arch detection (returns "jvm" on Kotlin backend)
let arch = asm_arch()
print(arch)
