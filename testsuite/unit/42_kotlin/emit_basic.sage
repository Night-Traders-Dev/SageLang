## Test: Kotlin backend — basic expressions and statements
## Run: sage --emit-kotlin tests/42_kotlin/emit_basic.sage

let x = 10
let name = "Sage"
let flag = true
let nothing = nil

print(x)
print(name)
print(flag)
print(nothing)

## Arithmetic
let a = 10 + 20
let b = a * 3
let c = b / 2
let d = 100 % 7
print(a)
print(b)
print(c)
print(d)

## String ops
let greeting = "Hello, " + name + "!"
print(greeting)
print(len(greeting))

## Comparisons
print(10 > 5)
print(10 == 10)
print(10 != 5)
print(10 <= 10)

## Logical
print(true and false)
print(true or false)
print(not false)

## Type conversion
print(str(42))
print(tonumber("3.14"))
print(type(42))
print(type("hello"))
