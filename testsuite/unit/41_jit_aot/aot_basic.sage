# EXPECT: 4950
# EXPECT: 55
# EXPECT: hello world
let sum = 0
let i = 0
while i < 100:
    sum = sum + i
    i = i + 1
print sum

proc fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)
print fib(10)

print "hello " + "world"
