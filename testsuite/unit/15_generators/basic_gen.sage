# EXPECT: 1
# EXPECT: 2
# EXPECT: 3
proc counter():
    yield 1
    yield 2
    yield 3
let g = counter()
print(next(g))
print(next(g))
print(next(g))
