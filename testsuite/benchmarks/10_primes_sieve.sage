# Prime sieve — measures array access and conditional logic
let limit = 10000
let sieve = []
let i = 0
while i < limit:
    push(sieve, true)
    i = i + 1

sieve[0] = false
sieve[1] = false

let p = 2
while p * p < limit:
    if sieve[p] == true:
        let m = p * p
        while m < limit:
            sieve[m] = false
            m = m + p
    p = p + 1

let count = 0
let k = 0
while k < limit:
    if sieve[k] == true:
        count = count + 1
    k = k + 1

print count
