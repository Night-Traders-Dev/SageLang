# Test dead code elimination
proc used_func(a, b):
    return a + b

let result = used_func(3, 7)
print result
print "alive"
