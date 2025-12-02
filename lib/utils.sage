# Utility Functions Module
# Common utility and helper functions

proc is_even(n):
    let remainder = n - (n / 2) * 2
    if remainder == 0:
        return true
    return false

proc is_odd(n):
    return not is_even(n)

proc clamp(value, min_val, max_val):
    if value < min_val:
        return min_val
    if value > max_val:
        return max_val
    return value

proc swap(a, b):
    # Returns tuple with swapped values
    return (b, a)

proc sign(x):
    if x > 0:
        return 1
    if x < 0:
        return 0 - 1
    return 0
