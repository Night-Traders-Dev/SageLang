# EXPECT: 120
# EXPECT: 8
proc factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)
print(factorial(5))
proc fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)
print(fib(6))
