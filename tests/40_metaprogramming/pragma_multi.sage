# EXPECT: deprecated called
# EXPECT: 7
# Test multiple pragmas on a single declaration

@inline
@deprecated
proc old_add(a, b):
    print "deprecated called"
    return a + b

let result = old_add(3, 4)
print result
