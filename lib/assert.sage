from math import abs

proc fail(message):
    raise message

proc assert_true(condition, message):
    if condition == false:
        raise message
    return true

proc assert_false(condition, message):
    if condition:
        raise message
    return true

proc assert_equal(actual, expected, message):
    if actual != expected:
        raise message
    return true

proc assert_nil(value, message):
    if value != nil:
        raise message
    return true

proc assert_not_nil(value, message):
    if value == nil:
        raise message
    return true

proc assert_close(actual, expected, tolerance, message):
    if abs(actual - expected) > tolerance:
        raise message
    return true

proc assert_array_contains(values, expected, message):
    for item in values:
        if item == expected:
            return true
    raise message
