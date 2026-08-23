proc add(a, b):
    return a + b
proc apply(f, x):
    return f(x)
print add(2, 3)
print apply(add, 10)
let anon = proc(x): return x * 2 end
print anon(21)
proc outer():
    let n = 10
    proc inner():
        return n + 1
    return inner()
print outer()
