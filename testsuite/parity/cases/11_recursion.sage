proc fib(n):
    if n <= 1:
        return n
    end
    return fib(n - 1) + fib(n - 2)
end
print fib(12)
proc gcd(a, b):
    if b == 0:
        return a
    end
    return gcd(b, a % b)
end
print gcd(48, 18)
