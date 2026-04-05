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
    let i = 0
    while i < count:
        yield value
        i = i + 1

proc repeat_forever(value):
    while true:
        yield value

proc enumerate_array(values):
    let i = 0
    while i < len(values):
        yield (i, values[i])
        i = i + 1

proc cycle(values):
    if len(values) == 0:
        return nil

    let i = 0
    while true:
        yield values[i]
        i = i + 1
        if i >= len(values):
            i = 0

proc take(gen, count):
    let result = []
    let i = 0
    while i < count:
        push(result, next(gen))
        i = i + 1
    return result

proc nth(gen, index):
    let value = nil
    let i = 0
    while i <= index:
        value = next(gen)
        i = i + 1
    return value
