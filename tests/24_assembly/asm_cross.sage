# Test cross-compilation to aarch64 and rv64
# EXPECT: true
# EXPECT: true

# Cross-compile aarch64 assembly
let ok1 = asm_compile("    mov x0, #42", "aarch64", "/tmp/sage_test_aarch64.o")
print ok1

# Cross-compile RISC-V 64 assembly
let ok2 = asm_compile("    li a0, 42", "rv64", "/tmp/sage_test_rv64.o")
print ok2
