proc add(x, y):
    return (x + y)

proc sub(x, y):
    return (x - y)

proc mul(x, y):
    return (x * y)

proc div(x, y):
    if (y == 0):
        return 0
    return (x / y)

proc abs(x):
    if x < 0:
        return (0 - x)
    return x

proc sqrt(n):
    if n <= 0:
        return 0

    let guess = n
    let i = 0
    while i < 16:
        guess = (guess + (n / guess)) / 2
        i = i + 1

    return guess
