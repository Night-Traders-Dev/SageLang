# math.sage — Core math library for SageLang
# Uses comptime for constants and @inline for hot-path arithmetic.

import _math
from _math import *

# ============================================================================
# Inline arithmetic primitives
# ============================================================================

## Add two numbers
@inline
proc add(x, y):
    return x + y

## Subtract two numbers
@inline
proc sub(x, y):
    return x - y

## Multiply two numbers
@inline
proc mul(x, y):
    return x * y

## Divide two numbers
@inline
proc div(x, y):
    if y == 0:
        return 0
    return x / y

## Returns 1 if x > 0, -1 if x < 0, 0 otherwise
@inline
proc sign(x):
    if x > 0:
        return 1
    if x < 0:
        return 0 - 1
    return 0

## Returns the square of x
@inline
proc square(x):
    return x * x

## Returns the cube of x
@inline
proc cube(x):
    return x * x * x

## Linear interpolation between a and b by t
@inline
proc lerp(a, b, t):
    return a + (b - a) * t

## Binary exponentiation: base ^ exponent
proc pow_int(base, exponent):
    if exponent == 0:
        return 1
    if exponent < 0:
        return 1 / pow_int(base, 0 - exponent)

    let res = 1
    let b = base
    let e = exponent
    while e > 0:
        if e % 2 == 1:
            res = res * b
        b = b * b
        e = int(e / 2)
    return res

## Returns the factorial of n
proc factorial(n):
    if n <= 1:
        return 1

    let result = 1
    let i = 2
    while i <= n:
        result = result * i
        i = i + 1
    return result

## Returns the greatest common divisor of a and b
proc gcd(a, b):
    a = abs(a)
    b = abs(b)

    while b != 0:
        let temp = b
        b = a % b
        a = temp

    return a

## Returns the least common multiple of a and b
@inline
proc lcm(a, b):
    if a == 0 or b == 0:
        return 0
    return abs(a * b) / gcd(a, b)

## Returns the sum of a list of values
proc sum(values):
    let total_sum = 0
    for item in values:
        total_sum = total_sum + item
    return total_sum

## Returns the product of a list of values
proc product(values):
    let total_prod = 1
    for item in values:
        total_prod = total_prod * item
    return total_prod

## Returns the arithmetic mean of a list of values
@inline
proc mean(values):
    if len(values) == 0:
        return 0
    return sum(values) / len(values)

## Returns the squared distance between (x1, y1) and (x2, y2)
@inline
proc distance_sq(x1, y1, x2, y2):
    let dx = x2 - x1
    let dy = y2 - y1
    return dx * dx + dy * dy

## Returns the Euclidean distance between (x1, y1) and (x2, y2)
@inline
proc distance(x1, y1, x2, y2):
    return sqrt(distance_sq(x1, y1, x2, y2))

## Normalizes value between min_val and max_val to [0, 1]
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

# Initialize seed with a value from the native PRNG for unpredictability
let _random_seed = int(_math.random() * 4294967296.0)

comptime:
    let _LCG_A = 1664525
    let _LCG_C = 1013904223
    let _LCG_M = 4294967296

## Internal helper to generate next random seed
proc _random_next():
    _random_seed = (_random_seed * _LCG_A + _LCG_C) % _LCG_M
    return _random_seed

## Returns a random float in [0, 1)
@inline
proc random():
    return _random_next() / 4294967296.0

## Returns a random float in [min_val, max_val)
@inline
proc random_range(min_val, max_val):
    return min_val + random() * (max_val - min_val)

## Returns a random integer in [min_val, max_val]
@inline
proc random_int(min_val, max_val):
    return int(random_range(min_val, max_val + 1))

# ============================================================================
# Type conversion
# ============================================================================

# Note: abs, min, max, clamp, sqrt, floor, ceil, round, and int
# are now provided natively via _math or builtins.
