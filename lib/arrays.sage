proc copy(values):
    let result = []
    for item in values:
        push(result, item)
    return result

proc append_all(target, extra):
    for item in extra:
        push(target, item)
    return target

proc concat(left, right):
    let result = copy(left)
    append_all(result, right)
    return result

proc reverse(values):
    let result = []
    let i = len(values) - 1
    while i >= 0:
        push(result, values[i])
        i = i - 1
    return result

proc map(values, fn):
    let result = []
    for item in values:
        push(result, fn(item))
    return result

proc filter(values, predicate):
    let result = []
    for item in values:
        if predicate(item):
            push(result, item)
    return result

proc reduce(values, initial, fn):
    let result = initial
    for item in values:
        result = fn(result, item)
    return result

proc contains(values, needle):
    for item in values:
        if item == needle:
            return true
    return false

proc index_of(values, needle):
    let i = 0
    while i < len(values):
        if values[i] == needle:
            return i
        i = i + 1
    return 0 - 1

proc find(values, predicate):
    for item in values:
        if predicate(item):
            return item
    return nil

proc unique(values):
    let result = []
    for item in values:
        if contains(result, item) == false:
            push(result, item)
    return result

proc flatten(nested):
    let result = []
    for group in nested:
        for item in group:
            push(result, item)
    return result

proc take(values, count):
    let result = []
    let i = 0
    while i < len(values) and i < count:
        push(result, values[i])
        i = i + 1
    return result

proc drop(values, count):
    let result = []
    let i = count
    while i < len(values):
        push(result, values[i])
        i = i + 1
    return result

proc zip(left, right):
    let result = []
    let limit = len(left)
    if len(right) < limit:
        limit = len(right)

    let i = 0
    while i < limit:
        push(result, (left[i], right[i]))
        i = i + 1
    return result

proc chunk(values, size):
    let result = []
    if size <= 0:
        return result

    let current = []
    let i = 0
    while i < len(values):
        push(current, values[i])
        if len(current) == size:
            push(result, current)
            current = []
        i = i + 1

    if len(current) > 0:
        push(result, current)

    return result
