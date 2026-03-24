# Closures and higher-order functions — measures closure overhead
proc make_adder(n):
    proc add(x):
        return x + n
    return add

let add5 = make_adder(5)
let add10 = make_adder(10)

let total = 0
let i = 0
while i < 100000:
    total = total + add5(i) + add10(i)
    i = i + 1

print total
