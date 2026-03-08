proc add(x, y):
    return x + y

proc sub(x, y):
    return x - y

proc mul(x, y):
    return x * y

proc div(x, y):
    if y == 0:
        return 0
    return x / y

proc min(a, b):
    if a < b:
        return a
    return b

proc max(a, b):
    if a > b:
        return a
    return b

proc abs(x):
    if x < 0:
        return 0 - x
    return x

proc sign(x):
    if x > 0:
        return 1
    if x < 0:
        return 0 - 1
    return 0

proc clamp(value, min_val, max_val):
    if value < min_val:
        return min_val
    if value > max_val:
        return max_val
    return value

proc square(x):
    return x * x

proc cube(x):
    return x * x * x

proc lerp(a, b, t):
    return a + (b - a) * t

proc pow_int(base, exponent):
    if exponent == 0:
        return 1
    if exponent < 0:
        return 1 / pow_int(base, 0 - exponent)

    let result = 1
    let i = 0
    while i < exponent:
        result = result * base
        i = i + 1
    return result

proc factorial(n):
    if n <= 1:
        return 1

    let result = 1
    let i = 2
    while i <= n:
        result = result * i
        i = i + 1
    return result

proc gcd(a, b):
    a = abs(a)
    b = abs(b)

    while b != 0:
        let temp = b
        b = a % b
        a = temp

    return a

proc lcm(a, b):
    if a == 0 or b == 0:
        return 0
    return abs(a * b) / gcd(a, b)

proc sum(values):
    let total = 0
    for item in values:
        total = total + item
    return total

proc product(values):
    let total = 1
    for item in values:
        total = total * item
    return total

proc mean(values):
    if len(values) == 0:
        return 0
    return sum(values) / len(values)

proc sqrt(n):
    if n <= 0:
        return 0

    let guess = n
    let i = 0
    while i < 16:
        guess = (guess + (n / guess)) / 2
        i = i + 1

    return guess

proc distance_sq(x1, y1, x2, y2):
    let dx = x2 - x1
    let dy = y2 - y1
    return dx * dx + dy * dy

proc distance(x1, y1, x2, y2):
    return sqrt(distance_sq(x1, y1, x2, y2))

proc normalize(value, min_val, max_val):
    if max_val == min_val:
        return 0
    return (value - min_val) / (max_val - min_val)
