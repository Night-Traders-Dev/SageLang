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

proc min_value(values):
    if len(values) == 0:
        return nil

    let current = values[0]
    let i = 1
    while i < len(values):
        if values[i] < current:
            current = values[i]
        i = i + 1
    return current

proc max_value(values):
    if len(values) == 0:
        return nil

    let current = values[0]
    let i = 1
    while i < len(values):
        if values[i] > current:
            current = values[i]
        i = i + 1
    return current

proc mean(values):
    if len(values) == 0:
        return 0
    return sum(values) / len(values)

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

proc stddev(values):
    return sqrt(variance(values))

proc normalize(values):
    let result = []
    if len(values) == 0:
        return result

    let low = min_value(values)
    let high = max_value(values)
    let span = high - low

    if span == 0:
        let i = 0
        while i < len(values):
            push(result, 0)
            i = i + 1
        return result

    for item in values:
        push(result, (item - low) / span)
    return result
