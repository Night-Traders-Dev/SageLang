# math.sage — Core math library for SageLang
# Uses comptime for constants and @inline for hot-path arithmetic.

# ============================================================================
# Inline arithmetic primitives
# ============================================================================

@inline
proc add(x, y):
    return x + y

@inline
proc sub(x, y):
    return x - y

@inline
proc mul(x, y):
    return x * y

@inline
proc div(x, y):
    if y == 0:
        return 0
    return x / y

@inline
proc min(a, b):
    if a < b:
        return a
    return b

@inline
proc max(a, b):
    if a > b:
        return a
    return b

@inline
proc abs(x):
    if x < 0:
        return 0 - x
    return x

@inline
proc sign(x):
    if x > 0:
        return 1
    if x < 0:
        return 0 - 1
    return 0

@inline
proc clamp(value, min_val, max_val):
    if value < min_val:
        return min_val
    if value > max_val:
        return max_val
    return value

@inline
proc square(x):
    return x * x

@inline
proc cube(x):
    return x * x * x

@inline
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

@inline
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

@inline
proc mean(values):
    if len(values) == 0:
        return 0
    return sum(values) / len(values)

@inline
proc sqrt(n):
    if n <= 0:
        return 0

    let guess = n
    let i = 0
    while i < 16:
        guess = (guess + (n / guess)) / 2
        i = i + 1

    return guess

@inline
proc distance_sq(x1, y1, x2, y2):
    let dx = x2 - x1
    let dy = y2 - y1
    return dx * dx + dy * dy

@inline
proc distance(x1, y1, x2, y2):
    return sqrt(distance_sq(x1, y1, x2, y2))

@inline
proc normalize(value, min_val, max_val):
    if max_val == min_val:
        return 0
    return (value - min_val) / (max_val - min_val)

# ============================================================================
# Constants — evaluated at compile time
# ============================================================================

comptime:
    let PI = 3.14159265358979323846
    let E = 2.71828182845904523536

# ============================================================================
# Random number generation (Linear Congruential Generator)
# ============================================================================

comptime:
    let _random_seed = 123456789
    let _LCG_A = 1664525
    let _LCG_C = 1013904223
    let _LCG_M = 4294967296

proc _random_next():
    _random_seed = (_random_seed * _LCG_A + _LCG_C) % _LCG_M
    return _random_seed

@inline
proc random():
    return _random_next() / 4294967296.0

@inline
proc random_range(min_val, max_val):
    return min_val + random() * (max_val - min_val)

@inline
proc random_int(min_val, max_val):
    return int(random_range(min_val, max_val + 1))

# ============================================================================
# Type conversion
# ============================================================================

proc int(value):
    if value < 0:
        return 0 - floor(0 - value)
    return floor(value)

proc floor(value):
    let int_part = 0
    if value >= 0:
        while int_part <= value:
            int_part = int_part + 1
        return int_part - 1
    else:
        while int_part > value:
            int_part = int_part - 1
        return int_part

proc ceil(value):
    let int_part = floor(value)
    if value == int_part:
        return int_part
    if value > 0:
        return int_part + 1
    return int_part

@inline
proc round(value):
    if value >= 0:
        return floor(value + 0.5)
    return ceil(value - 0.5)
