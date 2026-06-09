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

let fib_result = fib(25)
print("fib(25) = " + str(fib_result))

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
while i < 10000:
    push(arr, i)
    i = i + 1
let arr_sum = 0
i = 0
while i < len(arr):
    arr_sum = arr_sum + arr[i]
    i = i + 1
print("array_sum(10000) = " + str(arr_sum))

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

let primes_count = sieve(20000)
print("primes(20000) = " + str(primes_count))

## --- 7. Nested loops ---
let nested_sum = 0
i = 0
while i < 200:
    let j = 0
    while j < 200:
        nested_sum = nested_sum + 1
        j = j + 1
    i = i + 1
print("nested(200x200) = " + str(nested_sum))

## --- 8. LCG hash (integer arithmetic hot path) ---
let lcg = 12345
i = 0
while i < 100000:
    lcg = (lcg * 1103515245 + 12345) % 2147483647
    i = i + 1
print("lcg(100000) = " + str(lcg))

## --- 9. Tuple operations ---
let tuple_sum = 0
i = 0
while i < 100000:
    let t = (i, i + 1, i + 2)
    tuple_sum = tuple_sum + t[0] + t[1] + t[2]
    i = i + 1
print("tuple_sum(100000) = " + str(tuple_sum))

## --- 10. Boolean and Nil logic ---
let bool_count = 0
i = 0
while i < 100000:
    let b = (i % 2 == 0)
    let n = nil
    if b or n != nil:
        bool_count = bool_count + 1
    end
    i = i + 1
print("bool_count(100000) = " + str(bool_count))

## --- 11. Bytes operations ---
let b_buf = bytes(10000)
i = 0
while i < 10000:
    b_buf[i] = i % 256
    i = i + 1
var b_sum = 0
i = 0
while i < 10000:
    b_sum = b_sum + b_buf[i]
    i = i + 1
print("bytes_sum(10000) = " + str(b_sum))

## --- 12. Inline Assembly (if supported) ---
let asm_val = 0
if asm_arch() != "unknown" and asm_arch() != "jvm":
    # Simple increment in x86/ARM/RISC-V
    let code = ""
    let arch = asm_arch()
    if arch == "x86_64":
        code = "mov %rdi, %rax; add $1, %rax; ret"
    elif arch == "aarch64":
        code = "add x0, x0, #1; ret"
    elif arch == "rv64":
        code = "addi a0, a0, 1; ret"
    end
    
    if code != "":
        i = 0
        while i < 1000:
            # Note: asm_exec overhead is high, we just want to prove it works
            # but let's do fewer iterations to not dwarf the whole bench
            asm_val = asm_exec(code, "int", i)
            i = i + 1
    end
end
print("asm_val(1000) = " + str(asm_val))
