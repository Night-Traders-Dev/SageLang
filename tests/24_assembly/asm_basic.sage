# Test basic inline assembly - return a constant
# EXPECT: 42

let result = asm_exec("    mov $42, %rax", "int")
print result
