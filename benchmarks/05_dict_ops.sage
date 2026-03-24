# Dictionary operations — measures hash table insert and lookup
let d = {}
let i = 0
while i < 10000:
    d[str(i)] = i * 3
    i = i + 1

let total = 0
let j = 0
while j < 10000:
    total = total + d[str(j)]
    j = j + 1

print total
print len(dict_keys(d))
