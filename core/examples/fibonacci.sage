# Fibonacci sequence examples
print "=== Fibonacci Sequence ==="
print ""

# Iterative approach
proc fib_iterative(n):
    if n <= 1:
        return n
    
    let prev = 0
    let curr = 1
    
    for i in range(2, n + 1):
        let next = prev + curr
        let prev = curr
        let curr = next
    
    return curr

# Recursive approach
proc fib_recursive(n):
    if n <= 1:
        return n
    return fib_recursive(n - 1) + fib_recursive(n - 2)

# Print first 10 Fibonacci numbers (iterative)
print "First 10 Fibonacci numbers (iterative):"
for i in range(10):
    print fib_iterative(i)

print ""
print "8th Fibonacci number (recursive):"
print fib_recursive(8)

print ""
print "Sequence complete!"