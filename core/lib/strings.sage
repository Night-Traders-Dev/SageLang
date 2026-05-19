# strings.sage — String manipulation utilities
# @inline on simple wrappers and hot string ops.

proc words(text):
    let raw = split(strip(text), " ")
    let result = []
    for part in raw:
        if part != "":
            push(result, part)
    return result

@inline
proc compact(text):
    return join(words(text), " ")

let _builtin_contains = contains

@inline
proc contains(text, part):
    return _builtin_contains(text, part)

@inline
proc count_substring(text, part):
    if part == "":
        return 0
    return len(split(text, part)) - 1

proc repeat(text, count):
    let pieces = []
    let i = 0
    while i < count:
        push(pieces, text)
        i = i + 1
    return join(pieces, "")

proc pad_left(text, width, pad):
    if len(text) >= width:
        return text
    return repeat(pad, width - len(text)) + text

proc pad_right(text, width, pad):
    if len(text) >= width:
        return text
    return text + repeat(pad, width - len(text))

@inline
proc surround(text, left, right):
    return left + text + right

@inline
proc csv(values):
    return join(values, ",")

@inline
proc dash_case(text):
    return lower(join(words(replace(text, "_", " ")), "-"))

@inline
proc snake_case(text):
    return lower(join(words(replace(text, "-", " ")), "_"))

let _builtin_endswith = endswith

proc endswith(a, b):
    return _builtin_endswith(a, b)

proc from_bin(bits):
    let start = 0
    if len(bits) >= 2:
        if bits[0] == "0":
            if bits[1] == "b":
                start = 2
    let result = 0
    let i = start
    while i < len(bits):
        result = result * 2
        if bits[i] == "1":
            result = result + 1
        i = i + 1
    return result
