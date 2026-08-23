proc gen():
    yield 1
    yield 2
    yield 3
let g = gen()
print next(g)
print next(g)
let vals = []
for v in gen():
    push(vals, v)
print vals
