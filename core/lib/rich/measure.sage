gc_disable()
# Text measurement utilities
# Measures visible width of strings (accounting for ANSI codes, unicode widths etc)

## Helper to check if a unicode character code is wide.
@inline
# Helper to check if a unicode character code is wide.
proc _is_wide_code(code):
    if code >= 0x1100 and code <= 0x115F:
        return true
    if code >= 0x2329 and code <= 0x232A:
        return true
    if code >= 0x2E80 and code <= 0xA4CF:
        return true
    if code >= 0xF900 and code <= 0xFAFF:
        return true
    if code >= 0xFE10 and code <= 0xFE19:
        return true
    if code >= 0xFF01 and code <= 0xFF60:
        return true
    if code >= 0xFFE0 and code <= 0xFFE6:
        return true
    return false

## Count visible characters in a string, stripping ANSI escape sequences.
proc measure_text(text):
    if text == nil:
        return 0
    let count = 0
    let txt = str(text)
    if type(text) == "string":
        txt = text
    let len_txt = len(txt)
    if contains(txt, chr(27)) == false:
        for idx in range(len_txt):
            if _is_wide_code(ord(txt[idx])):
                count = count + 2
            else:
                count = count + 1
        return count
    let i = 0
    while i < len_txt:
        if txt[i] == chr(27) and i + 1 < len_txt and txt[i + 1] == "[":
            # Skip ANSI escape sequence
            i = i + 2
            while i < len_txt:
                let esc_c = txt[i]
                if (esc_c >= "A" and esc_c <= "Z") or (esc_c >= "a" and esc_c <= "z"):
                    i = i + 1
                    break
                i = i + 1
            continue
        if _is_wide_code(ord(txt[i])):
            count = count + 2
        else:
            count = count + 1
        i = i + 1
    return count

## Measure width of a single character.
proc measure_char(c):
    if _is_wide_code(ord(c)):
        return 2
    return 1

## Get the maximum width of lines in text.
proc measure_max_width(text):
    let lines = split(text, chr(10))
    let max_w = 0
    for i in range(len(lines)):
        let w = measure_text(lines[i])
        if w > max_w:
            max_w = w
    return max_w

## Get the visible length of text after stripping ANSI.
proc visible_length(text):
    return measure_text(text)

## Strip ANSI escape sequences from a string.
proc strip_ansi(text):
    if text == nil:
        return ""
    if type(text) == "number":
        return str(text)
    if contains(text, chr(27)) == false:
        return text
    let parts = []
    let idx_ansi = 0
    let len_text = len(text)
    let last_start = 0
    while idx_ansi < len_text:
        if text[idx_ansi] == chr(27) and idx_ansi + 1 < len_text and text[idx_ansi + 1] == "[":
            if idx_ansi > last_start:
                push(parts, slice(text, last_start, idx_ansi))
            idx_ansi = idx_ansi + 2
            while idx_ansi < len_text:
                let strip_esc_c = text[idx_ansi]
                if (strip_esc_c >= "A" and strip_esc_c <= "Z") or (strip_esc_c >= "a" and strip_esc_c <= "z"):
                    idx_ansi = idx_ansi + 1
                    break
                idx_ansi = idx_ansi + 1
            last_start = idx_ansi
            continue
        idx_ansi = idx_ansi + 1
    if last_start < len_text:
        push(parts, slice(text, last_start, len_text))
    return join(parts, "")

## Pad text on the right to reach a certain visual width.
proc pad_right_to_width(text, width, pad_ch):
    if pad_ch == nil:
        pad_ch = " "
    let visible_w = measure_text(text)
    if visible_w >= width:
        return text
    return text + string_repeat(pad_ch, width - visible_w)

## Pad text on the left to reach a certain visual width.
proc pad_left_to_width(text, width, pad_ch):
    if pad_ch == nil:
        pad_ch = " "
    let left_visible_w = measure_text(text)
    if left_visible_w >= width:
        return text
    return string_repeat(pad_ch, width - left_visible_w) + text

## Center text within a given width.
proc center_text(text, width, pad_ch):
    if pad_ch == nil:
        pad_ch = " "
    let center_visible_w = measure_text(text)
    if center_visible_w >= width:
        return text
    let left_pad = (width - center_visible_w) / 2
    left_pad = left_pad | 0
    let right_pad = width - center_visible_w - left_pad
    return string_repeat(pad_ch, left_pad) + text + string_repeat(pad_ch, right_pad)
