# REQUIRES-ARCH: x86_64
# Writes x86_64 assembly (mov $42, %rax) and runs it through the system assembler.
# Test basic inline assembly - return a constant
# EXPECT: 42

let result = asm_exec("    mov $42, %rax", "int")
print result
