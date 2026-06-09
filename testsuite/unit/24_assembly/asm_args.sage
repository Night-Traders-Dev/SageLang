# Test inline assembly with arguments
# EXPECT: 42
# EXPECT: 42
# EXPECT: 100

# Add two numbers (System V ABI: rdi + rsi)
let sum = asm_exec("    mov %rdi, %rax\n    add %rsi, %rax", "int", 10, 32)
print sum

# Multiply two numbers
let product = asm_exec("    mov %rdi, %rax\n    imul %rsi, %rax", "int", 7, 6)
print product

# Three arguments: a + b + c
let sum3 = asm_exec("    mov %rdi, %rax\n    add %rsi, %rax\n    add %rdx, %rax", "int", 30, 30, 40)
print sum3
