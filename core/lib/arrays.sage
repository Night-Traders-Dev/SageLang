# arrays.sage — Array manipulation utilities
# Hot-path search and iteration procs marked @inline for compiled backends.

proc copy(values):
    return slice(values, 0, len(values))

proc append_all(target, extra):
    array_extend(target, extra)
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

@inline
proc contains(values, needle):
    for item in values:
        if item == needle:
            return true
    return false

@inline
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
    ## Returns a new array containing only the unique elements of the input.
    ## Uses a dictionary for O(n) average-case lookup performance.
    let result = []
    let seen = {}
    for item in values:
        let key = str(item) + type(item)
        if dict_has(seen, key) == false:
            seen[key] = [item]
            push(result, item)
        else:
            let bucket = seen[key]
            let found = false
            for x in bucket:
                if x == item:
                    found = true
                    break
            if found == false:
                push(bucket, item)
                push(result, item)
    return result

## Flattens a nested array into a single array.
proc flatten(nested):
    let result = []
    for group in nested:
        array_extend(result, group)
    return result

## Returns a new array with the first 'count' elements.
## Optimization: Uses native slice() to avoid interpreter loop overhead.
@inline
proc take(values, count):
    if count <= 0:
        return []
    return slice(values, 0, count)

## Returns a new array with all but the first 'count' elements.
## Optimization: Uses native slice() to avoid interpreter loop overhead.
@inline
proc drop(values, count):
    return slice(values, count, len(values))

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
