# iter.sage — Generator/iterator utilities
# Generators cannot be @inline (they use yield), but non-yield helpers are.

proc count(start, step):
    let current = start
    while true:
        yield current
        current = current + step

proc range_step(start, stop, step):
    if step == 0:
        return nil

    let current = start
    if step > 0:
        while current < stop:
            yield current
            current = current + step
    else:
        while current > stop:
            yield current
            current = current + step

proc repeat(value, count):
    for i in range(count):
        yield value

proc repeat_forever(value):
    while true:
        yield value

proc enumerate_array(values):
    for i in range(len(values)):
        yield (i, values[i])

proc cycle(values):
    if len(values) == 0:
        return nil

    while true:
        for x in values:
            yield x

@inline
proc take(gen, count):
    let result = []
    for i in range(count):
        push(result, next(gen))
    return result

@inline
proc nth(gen, index):
    let value = nil
    for i in range(index + 1):
        value = next(gen)
    return value
