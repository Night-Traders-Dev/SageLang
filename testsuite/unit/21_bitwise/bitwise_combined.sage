# Test combined bitwise operations
# EXPECT: 15
# EXPECT: true
# EXPECT: 240

# Mask and shift: extract bits 0-3 from 0xFF
let val = 255
let mask = 15
print val & mask

# Check if bit 2 is set in 7
let x = 7
let bit2 = (x >> 2) & 1
print bit2 == 1

# Set upper nibble: shift 15 left by 4
print 15 << 4
