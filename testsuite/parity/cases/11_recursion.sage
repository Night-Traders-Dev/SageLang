proc fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)
print fib(12)
proc gcd(a, b):
    if b == 0:
        return a
    return gcd(b, a % b)
print gcd(48, 18)
