import sys

# Test cross-compilation to aarch64 and rv64
# Results are true when cross-assemblers are installed, or skipped gracefully
# EXPECT: true
# EXPECT: true

# Cross-compile aarch64 assembly (requires aarch64-linux-gnu-as)
let has_aarch64_as = sys.shell_exec("which aarch64-linux-gnu-as") != ""
if has_aarch64_as:
    asm_compile("    mov x0, #42", "aarch64", "/tmp/sage_test_aarch64.o")
print true

# Cross-compile RISC-V 64 assembly (requires riscv64-linux-gnu-as)
let has_rv64_as = sys.shell_exec("which riscv64-linux-gnu-as") != ""
if has_rv64_as:
    asm_compile("    li a0, 42", "rv64", "/tmp/sage_test_rv64.o")
print true
