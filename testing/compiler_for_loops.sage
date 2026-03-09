# Test for-in loops in C backend
let total = 0
let arr = [10, 20, 30]
for x in arr:
    total = total + x
print total

# For loop with range
let sum = 0
for i in range(5):
    sum = sum + i
print sum

# Nested for loop
let result = 0
for i in [1, 2]:
    for j in [10, 20]:
        result = result + i * j
print result
