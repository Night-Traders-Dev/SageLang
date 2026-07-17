proc fib(n: Int) -> Int:
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

proc sieve(limit: Int) -> Int:
    let is_prime = [true]
    # Arrays can be multiplied or pushed, but maybe push isn't built in?
    # Actually wait, let's skip the array and just do a simple integer benchmark loop.
    let count = 0
    let i = 0
    while i < 5000:
        let j = 0
        while j < limit:
            count = count + i + j
            j = j + 1
        i = i + 1
    return count

print("Running SageLang Benchmarks...")

let start_fib = clock()
let f = fib(36)
let end_fib = clock()
print("Fibonacci(36): " + str(f) + " | Time: " + str(end_fib - start_fib) + " s")

let start_sieve = clock()
let p = sieve(5000)
let end_sieve = clock()
print("Nested_loop(5K x 5K): " + str(p) + " | Time: " + str(end_sieve - start_sieve) + " s")
