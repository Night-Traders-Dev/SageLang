proc fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

proc accumulate(limit):
    let total = 0
    let current = 1
    while current <= limit:
        total = total + current
        current = current + 1
    return total

let counter = 0
while counter < 3:
    counter = counter + 1

print counter

let answer = fib(6)
print answer
print accumulate(5)
print "fib=" + str(fib(5))

if answer == 8:
    print "phase10-ok"
else:
    print "phase10-bad"
