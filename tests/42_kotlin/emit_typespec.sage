## Test: Kotlin backend — type specialization at -O2
## Run: sage --emit-kotlin tests/42_kotlin/emit_typespec.sage -O2

## These variables should be specialized to native types at -O2+
let x = 10
let y = 20
let sum = x + y
print(sum)

let name = "Sage"
let flag = true

## Mixed operations should still work
let result = x * y + 5
print(result)

## Loop with specialized counter
let total = 0
let i = 0
while i < 100:
    total = total + i
    i = i + 1
print(total)
