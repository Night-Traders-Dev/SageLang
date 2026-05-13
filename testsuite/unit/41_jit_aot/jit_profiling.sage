# EXPECT: 6765
# EXPECT: 19900
# Hot function — triggers JIT compilation
proc fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)
print fib(20)

# Another hot function
proc add(a, b):
    return a + b
let total = 0
let i = 0
while i < 200:
    total = add(total, i)
    i = i + 1
print total
