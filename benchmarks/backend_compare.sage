## backend_compare.sage — Cross-backend performance benchmark
##
## Tests all Sage execution backends on the same workloads:
##   1. Fibonacci (recursive function calls)
##   2. Loop sum (tight arithmetic loop)
##   3. Array operations (push/iterate)
##   4. String concatenation
##   5. Dict operations (insert/lookup)
##   6. Prime sieve (algorithmic)
##   7. Nested loops (control flow)
##   8. LCG hash (integer arithmetic hot path)
##
## Run:  sage benchmarks/backend_compare.sage
##
## Compares: interpreter (AST), C-compiled, LLVM-compiled, native asm
## Each workload prints its result for checksum validation.

## --- 1. Fibonacci ---
proc fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

let fib_result = fib(28)
print("fib(28) = " + str(fib_result))

## --- 2. Loop sum ---
let total = 0
let i = 0
while i < 100000:
    total = total + i
    i = i + 1
print("sum(0..99999) = " + str(total))

## --- 3. Array operations ---
let arr = []
i = 0
while i < 50000:
    push(arr, i)
    i = i + 1
let arr_sum = 0
i = 0
while i < len(arr):
    arr_sum = arr_sum + arr[i]
    i = i + 1
print("array_sum(50000) = " + str(arr_sum))

## --- 4. String concatenation ---
let s = ""
i = 0
while i < 1000:
    s = s + "x"
    i = i + 1
print("string_len = " + str(len(s)))

## --- 5. Dict operations ---
let d = {}
i = 0
while i < 10000:
    d[str(i)] = i * i
    i = i + 1
let dict_sum = 0
let keys = dict_keys(d)
i = 0
while i < len(keys):
    dict_sum = dict_sum + d[keys[i]]
    i = i + 1
print("dict_sum(10000) = " + str(dict_sum))

## --- 6. Prime sieve ---
proc sieve(limit):
    let is_prime = []
    let si = 0
    while si <= limit:
        push(is_prime, true)
        si = si + 1
    is_prime[0] = false
    is_prime[1] = false
    si = 2
    while si * si <= limit:
        if is_prime[si]:
            let j = si * si
            while j <= limit:
                is_prime[j] = false
                j = j + si
        si = si + 1
    let count = 0
    si = 2
    while si <= limit:
        if is_prime[si]:
            count = count + 1
        si = si + 1
    return count

let primes = sieve(100000)
print("primes(100000) = " + str(primes))

## --- 7. Nested loops ---
let nested_sum = 0
i = 0
while i < 500:
    let j = 0
    while j < 500:
        nested_sum = nested_sum + 1
        j = j + 1
    i = i + 1
print("nested(500x500) = " + str(nested_sum))

## --- 8. LCG hash (integer arithmetic hot path) ---
let lcg = 12345
i = 0
while i < 100000:
    lcg = (lcg * 1103515245 + 12345) % 2147483647
    i = i + 1
print("lcg(100000) = " + str(lcg))
