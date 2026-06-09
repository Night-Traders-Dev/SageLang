# EXPECT: 55
# EXPECT: hello from comptime
# EXPECT: 256
# Test comptime blocks — execute code at compile time

# Basic comptime block with a computed value
comptime:
    let sum = 0
    for i in range(11):
        sum = sum + i
    print sum

# Comptime block with string
comptime:
    let msg = "hello from comptime"
    print msg

# Comptime block with power computation
comptime:
    let base = 2
    let result = 1
    for i in range(8):
        result = result * base
    print result
