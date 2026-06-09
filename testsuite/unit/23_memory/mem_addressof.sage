# Test addressof function
# EXPECT: true
# EXPECT: true

# addressof returns a number (memory address)
let arr = [1, 2, 3]
let addr = addressof(arr)
print addr > 0

# Two different arrays have different addresses
let arr2 = [4, 5, 6]
let addr2 = addressof(arr2)
print addr != addr2
