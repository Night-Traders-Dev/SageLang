# Conformance: Lexical Scoping (Spec §5)
# EXPECT: 2
# EXPECT: 1
# EXPECT: inner
let x = 1
proc outer():
    let x = 2
    proc inner():
        return x
    return inner()
print outer()
print x

# Closures capture defining scope
proc make_greeter(greeting):
    proc greet():
        return greeting
    return greet

let g = make_greeter("inner")
print g()
