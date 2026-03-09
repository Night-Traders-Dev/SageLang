# EXPECT: 300
# Test multiple async procs running in parallel
async proc square(x):
    return x * x

let a = square(10)
let b = square(10)
let c = square(10)
print await a + await b + await c
