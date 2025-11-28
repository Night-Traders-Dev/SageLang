# Sage Generators - Phase 7 Examples
# Demonstrating yield and lazy evaluation

print "=== Example 1: Basic Generator ==="
proc count_up_to(n):
    let i = 0
    while i < n:
        yield i
        i = i + 1

let gen = count_up_to(5)
print next(gen)  # 0
print next(gen)  # 1
print next(gen)  # 2
print next(gen)  # 3
print next(gen)  # 4
print next(gen)  # nil (exhausted)

print ""
print "=== Example 2: Fibonacci Generator ==="
proc fibonacci():
    let a = 0
    let b = 1
    yield a
    yield b
    while true:
        let temp = a + b
        a = b
        b = temp
        yield b

let fib = fibonacci()
print next(fib)  # 0
print next(fib)  # 1
print next(fib)  # 1
print next(fib)  # 2
print next(fib)  # 3
print next(fib)  # 5
print next(fib)  # 8
print next(fib)  # 13

print ""
print "=== Example 3: Range Generator ==="
proc range_gen(start, end, step):
    let i = start
    while i < end:
        yield i
        i = i + step

let nums = range_gen(0, 10, 2)
print next(nums)  # 0
print next(nums)  # 2
print next(nums)  # 4
print next(nums)  # 6
print next(nums)  # 8

print ""
print "=== Example 4: Infinite Sequence ==="
proc naturals():
    let n = 0
    while true:
        yield n
        n = n + 1

let nat = naturals()
print next(nat)  # 0
print next(nat)  # 1
print next(nat)  # 2
print next(nat)  # 3
print next(nat)  # 4

print ""
print "=== Example 5: Generator with Conditional ==="
proc even_numbers(max):
    let i = 0
    while i <= max:
        if i % 2 == 0:
            yield i
        i = i + 1

let evens = even_numbers(10)
print next(evens)  # 0
print next(evens)  # 2
print next(evens)  # 4
print next(evens)  # 6
print next(evens)  # 8
print next(evens)  # 10

print ""
print "=== Example 6: Yield in Nested Loops ==="
proc nested_gen():
    let i = 0
    while i < 3:
        let j = 0
        while j < 2:
            yield i * 10 + j
            j = j + 1
        i = i + 1

let ng = nested_gen()
print next(ng)  # 0
print next(ng)  # 1
print next(ng)  # 10
print next(ng)  # 11
print next(ng)  # 20
print next(ng)  # 21

print ""
print "=== Example 7: Generator State Persistence ==="
proc counter():
    let count = 0
    while true:
        count = count + 1
        yield count

let c1 = counter()
let c2 = counter()

print next(c1)  # 1
print next(c2)  # 1
print next(c1)  # 2
print next(c1)  # 3
print next(c2)  # 2

print ""
print "All generator examples complete!"