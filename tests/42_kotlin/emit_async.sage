## Test: Kotlin backend — async/await with coroutines
## Run: sage --emit-kotlin tests/42_kotlin/emit_async.sage

async proc fetch_data():
    return 42

async proc compute(x):
    return x * 2

let result = await fetch_data()
print(result)

let doubled = await compute(21)
print(doubled)
