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
    # NOTE: SageLang v4.1.3 has a bug where 'yield' in 'for' doesn't advance state.
    # We must use 'while' for generators.
    let i = 0
    while i < count:
        yield value
        i = i + 1

proc repeat_forever(value):
    while true:
        yield value

proc enumerate_array(values):
    # NOTE: SageLang v4.1.3 has a bug where 'yield' in 'for' doesn't advance state.
    # We must use 'while' for generators.
    let i = 0
    let n = len(values)
    while i < n:
        yield (i, values[i])
        i = i + 1

proc cycle(values):
    # NOTE: SageLang v4.1.3 has a bug where 'yield' in 'for' doesn't advance state.
    # We must use 'while' for generators.
    let n = len(values)
    if n == 0:
        return nil

    while true:
        let i = 0
        while i < n:
            yield values[i]
            i = i + 1

@inline
proc take(gen, count):
    # Optimization: Uses 'for' loop for performance (~1.7x to 2.7x speedup).
    let result = []
    for i in range(count):
        push(result, next(gen))
    return result

@inline
proc nth(gen, index):
    # Optimization: Uses 'for' loop for performance (~1.7x to 2.7x speedup).
    let value = nil
    for i in range(index + 1):
        value = next(gen)
    return value
