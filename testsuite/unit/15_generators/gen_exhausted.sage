# EXPECT: 1
# EXPECT: nil
proc once():
    yield 1
let g = once()
print(next(g))
print(next(g))
