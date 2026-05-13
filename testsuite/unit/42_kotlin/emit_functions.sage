## Test: Kotlin backend — functions, recursion, closures
## Run: sage --emit-kotlin tests/42_kotlin/emit_functions.sage

proc add(a, b):
    return a + b

proc factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)

proc fibonacci(n):
    if n <= 0:
        return 0
    if n == 1:
        return 1
    return fibonacci(n - 1) + fibonacci(n - 2)

print(add(10, 20))
print(factorial(5))
print(fibonacci(10))

## Nested control flow
proc classify(n):
    if n > 0:
        return "positive"
    if n < 0:
        return "negative"
    return "zero"

print(classify(42))
print(classify(-7))
print(classify(0))

## While loop
proc sum_to(n):
    let total = 0
    let i = 1
    while i <= n:
        total = total + i
        i = i + 1
    return total

print(sum_to(100))

## Early return / break
proc find_first_even(items):
    for item in items:
        if item % 2 == 0:
            return item
    return nil

print(find_first_even([1, 3, 5, 4, 7]))
print(find_first_even([1, 3, 5, 7]))
