proc words(text):
    let raw = split(strip(text), " ")
    let result = []
    for part in raw:
        if part != "":
            push(result, part)
    return result

proc compact(text):
    return join(words(text), " ")

proc contains(text, part):
    if part == "":
        return true
    return len(split(text, part)) > 1

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

proc surround(text, left, right):
    return left + text + right

proc csv(values):
    return join(values, ",")

proc dash_case(text):
    return lower(join(words(replace(text, "_", " ")), "-"))

proc snake_case(text):
    return lower(join(words(replace(text, "-", " ")), "_"))

proc endswith(a, b):
    let end = split(a, "")
    if end[len(end) - 1] == b:
        return true
    else:
        return false

