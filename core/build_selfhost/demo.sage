proc fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)
end
let total = 0
let i = 0
while i < 1000:
    total = total + i
    i = i + 1
end
print("fib(15) = " + str(fib(15)))
print("sum(0..999) = " + str(total))
