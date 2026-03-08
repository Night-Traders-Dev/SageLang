proc identity(value):
    return value

proc choose(condition, when_true, when_false):
    if condition:
        return when_true
    return when_false

proc default_if_nil(value, fallback):
    if value == nil:
        return fallback
    return value

proc is_even(n):
    return n % 2 == 0

proc is_odd(n):
    return n % 2 != 0

proc between(value, lower, upper):
    if value < lower:
        return false
    if value > upper:
        return false
    return true

proc swap(a, b):
    return (b, a)

proc head(values):
    if len(values) == 0:
        return nil
    return values[0]

proc last(values):
    if len(values) == 0:
        return nil
    return values[len(values) - 1]

proc repeat_value(value, count):
    let result = []
    let i = 0
    while i < count:
        push(result, value)
        i = i + 1
    return result

proc times(count, fn):
    let i = 0
    while i < count:
        fn(i)
        i = i + 1
    return nil
