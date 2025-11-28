# Simple generator test
print "Testing basic generator"

proc simple_gen():
    print "Before yield"
    yield 42
    print "After yield"

print "Generator function defined"
let gen = simple_gen()
print "Generator created"
print gen
