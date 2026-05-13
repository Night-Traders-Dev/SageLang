# Prime sieve — measures array access and conditional logic
limit = 10000
sieve = [True] * limit

sieve[0] = False
sieve[1] = False

p = 2
while p * p < limit:
    if sieve[p]:
        m = p * p
        while m < limit:
            sieve[m] = False
            m = m + p
    p = p + 1

count = 0
k = 0
while k < limit:
    if sieve[k]:
        count = count + 1
    k = k + 1

print(count)
