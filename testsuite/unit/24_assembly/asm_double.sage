# Test inline assembly with double return type
# EXPECT: 4.2
# EXPECT: 6

# Add two doubles (xmm0 + xmm1)
let r1 = asm_exec("    addsd %xmm1, %xmm0", "double", 1.5, 2.7)
print r1

# Multiply two doubles
let r2 = asm_exec("    mulsd %xmm1, %xmm0", "double", 2.0, 3.0)
print r2
