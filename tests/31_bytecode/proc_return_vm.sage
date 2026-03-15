# RUN: bytecode-run
# EXPECT: 12
# EXPECT: 12
# EXPECT: nil

proc add(a, b):
    return a + b

proc twice(x):
    return add(x, x)

proc noop():
    let local = 99

print add(5, 7)
print twice(6)
print noop()
