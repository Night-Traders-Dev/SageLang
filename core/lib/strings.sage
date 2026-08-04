# strings.sage — String manipulation utilities
# @inline on simple wrappers and hot string ops.

# Splits a string into an array of words.
proc words(text):
    let raw = split(strip(text), " ")
    let result = []
    for part in raw:
        if part != "":
            push(result, part)
    return result

@inline
# Compacts consecutive whitespace in a string.
proc compact(text):
    return join(words(text), " ")

# contains is provided by the VM builtins and AOT prelude

@inline
# Returns the occurrences of 'part' in 'text'. (Uses native string_count).
proc count_substring(text, part):
    let res = string_count(text, part)
    if type(res) == "nil":
        if part == "":
            return 0
        return len(split(text, part)) - 1
    return res

@inline
# Repeats a string a given number of times. (Uses native string_repeat).
proc repeat(text, count):
    return string_repeat(text, count)

# Pads a string on the left with another string until it reaches the given width.
proc pad_left(text, width, pad):
    if len(text) >= width:
        return text
    return repeat(pad, width - len(text)) + text

# Pads a string on the right with another string until it reaches the given width.
proc pad_right(text, width, pad):
    if len(text) >= width:
        return text
    return text + repeat(pad, width - len(text))

@inline
# Surrounds a string with left and right parts.
proc surround(text, left, right):
    return left + text + right

@inline
# Joins an array of values into a comma-separated string.
proc csv(values):
    return join(values, ",")

@inline
# Converts a string to dash-case.
proc dash_case(text):
    return lower(join(words(replace(text, "_", " ")), "-"))

@inline
# Converts a string to snake-case.
proc snake_case(text):
    return lower(join(words(replace(text, "-", " ")), "_"))

# endswith is provided by the VM builtins and AOT prelude

# Converts a binary string to an integer.
# Converts a binary string to an integer.
proc from_bin(bits):
    let start_idx = 0
    if len(bits) >= 2:
        if bits[0] == "0":
            if bits[1] == "b":
                start_idx = 2
    let val_result = 0
    for i in range(start_idx, len(bits)):
        val_result = val_result * 2
        if bits[i] == "1":
            val_result = val_result + 1
    return val_result
