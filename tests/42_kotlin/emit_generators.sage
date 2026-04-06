## Test: Kotlin backend — generators with yield
## Run: sage --emit-kotlin tests/42_kotlin/emit_generators.sage

proc count_up(n):
    let i = 0
    while i < n:
        yield i
        i = i + 1

proc fibonacci_gen():
    let a = 0
    let b = 1
    while true:
        yield a
        let temp = a + b
        a = b
        b = temp

## Use generator in for loop
for x in count_up(5):
    print(x)
