# EXPECT: 15
proc make_adder(n):
    proc add(x):
        return x + n
    return add
let add5 = make_adder(5)
print(add5(10))
