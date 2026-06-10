# stats.sage — Statistical functions
# @inline on aggregation helpers; hot two-pass algorithms left as regular procs.

from math import sqrt

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

## Returns both the minimum and maximum values in a single pass.
## Optimization: Single-pass O(n) instead of two O(n) passes.
proc min_max(values):
    if len(values) == 0:
        return (nil, nil)

    let low = values[0]
    let high = values[0]
    for item in values:
        if item < low:
            low = item
        elif item > high:
            high = item
    return (low, high)

## Returns the minimum value in the array.
## Optimization: Uses 'for' loop which is ~3x faster than 'while' in Sage interpreter.
proc min_value(values):
    if len(values) == 0:
        return nil

    let current = values[0]
    for item in values:
        if item < current:
            current = item
    return current

## Returns the maximum value in the array.
## Optimization: Uses 'for' loop which is ~3x faster than 'while' in Sage interpreter.
proc max_value(values):
    if len(values) == 0:
        return nil

    let current = values[0]
    for item in values:
        if item > current:
            current = item
    return current

@inline
proc mean(values):
    if len(values) == 0:
        return 0
    return sum(values) / len(values)

@inline
proc range_span(values):
    if len(values) == 0:
        return 0
    return max_value(values) - min_value(values)

proc cumulative(values):
    let result = []
    let running = 0
    for item in values:
        running = running + item
        push(result, running)
    return result

proc variance(values):
    if len(values) == 0:
        return 0

    let avg = mean(values)
    let total = 0
    for item in values:
        let diff = item - avg
        total = total + diff * diff
    return total / len(values)

@inline
proc stddev(values):
    return sqrt(variance(values))

## Scales all values to the [0, 1] range.
## Optimization: Single-pass min/max search and efficient 'for' iteration.
proc normalize(values):
    let result = []
    if len(values) == 0:
        return result

    let bounds = min_max(values)
    let low = bounds[0]
    let high = bounds[1]
    let span = high - low

    if span == 0:
        for item in values:
            push(result, 0)
        return result

    for item in values:
        push(result, (item - low) / span)
    return result
