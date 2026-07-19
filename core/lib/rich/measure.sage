gc_disable()
# Text measurement utilities
# Measures visible width of strings (accounting for ANSI codes, unicode widths etc)

# Count visible characters in a string, stripping ANSI escape sequences
proc measure_text(text):
    if text == nil:
        return 0
    let count = 0
    let i = 0
    let txt = str(text)
    if type(text) == "string":
        txt = text
    while i < len(txt):
        if txt[i] == chr(27) and i + 1 < len(txt) and txt[i + 1] == "[":
            # Skip ANSI escape sequence
            i = i + 2
            while i < len(txt):
                let c = txt[i]
                if c >= "A" and c <= "Z" or c >= "a" and c <= "z":
                    i = i + 1
                    break
                i = i + 1
            continue
        # Handle combining characters and wide chars (basic)
        let code = ord(txt[i])
        if code >= 0x1100 and code <= 0x115F or code >= 0x2329 and code <= 0x232A or code >= 0x2E80 and code <= 0xA4CF or code >= 0xF900 and code <= 0xFAFF or code >= 0xFE10 and code <= 0xFE19 or code >= 0xFF01 and code <= 0xFF60 or code >= 0xFFE0 and code <= 0xFFE6:
            count = count + 2
        else:
            count = count + 1
        i = i + 1
    return count

# Measure width of a single character
proc measure_char(c):
    let code = ord(c)
    if code >= 0x1100 and code <= 0x115F or code >= 0x2329 and code <= 0x232A or code >= 0x2E80 and code <= 0xA4CF or code >= 0xF900 and code <= 0xFAFF or code >= 0xFE10 and code <= 0xFE19 or code >= 0xFF01 and code <= 0xFF60 or code >= 0xFFE0 and code <= 0xFFE6:
        return 2
    return 1

# Get the maximum width of lines in text
proc measure_max_width(text):
    let lines = split(text, chr(10))
    let max_w = 0
    for i in range(len(lines)):
        let w = measure_text(lines[i])
        if w > max_w:
            max_w = w
    return max_w

# Get the visible length of text after stripping ANSI
proc visible_length(text):
    return measure_text(text)

# Strip ANSI escape sequences from a string
proc strip_ansi(text):
    if text == nil:
        return ""
    if type(text) == "number":
        return str(text)
    let result = ""
    let i = 0
    while i < len(text):
        if text[i] == chr(27) and i + 1 < len(text) and text[i + 1] == "[":
            i = i + 2
            while i < len(text):
                let c = text[i]
                if c >= "A" and c <= "Z" or c >= "a" and c <= "z":
                    i = i + 1
                    break
                i = i + 1
            continue
        result = result + text[i]
        i = i + 1
    return result

# Pad text on the right to reach a certain visual width
proc pad_right_to_width(text, width, pad_ch):
    if pad_ch == nil:
        pad_ch = " "
    let visible = measure_text(text)
    if visible >= width:
        return text
    let padding = ""
    for i in range(width - visible):
        padding = padding + pad_ch
    return text + padding

# Pad text on the left to reach a certain visual width
proc pad_left_to_width(text, width, pad_ch):
    if pad_ch == nil:
        pad_ch = " "
    let visible = measure_text(text)
    if visible >= width:
        return text
    let padding = ""
    for i in range(width - visible):
        padding = padding + pad_ch
    return padding + text

# Center text within a given width
proc center_text(text, width, pad_ch):
    if pad_ch == nil:
        pad_ch = " "
    let visible = measure_text(text)
    if visible >= width:
        return text
    let left_pad = (width - visible) / 2
    left_pad = left_pad | 0
    let right_pad = width - visible - left_pad
    let left_str = ""
    for i in range(left_pad):
        left_str = left_str + pad_ch
    let right_str = ""
    for i in range(right_pad):
        right_str = right_str + pad_ch
    return left_str + text + right_str
