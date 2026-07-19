gc_disable()
import rich.measure

# Text alignment utilities

let ALIGN_LEFT = "left"
let ALIGN_CENTER = "center"
let ALIGN_RIGHT = "right"
let ALIGN_JUSTIFY = "justify"

# Align text within a given width
proc align(text, align, width, fill_char):
    if fill_char == nil:
        fill_char = " "
    if align == ALIGN_LEFT or align == nil:
        return rich.measure.pad_right_to_width(text, width, fill_char)
    if align == ALIGN_CENTER:
        return rich.measure.center_text(text, width, fill_char)
    if align == ALIGN_RIGHT:
        return rich.measure.pad_left_to_width(text, width, fill_char)
    if align == ALIGN_JUSTIFY:
        return justify_text(text, width, fill_char)
    return text

# Justify text to fill width
proc justify_text(text, width, fill_char):
    if fill_char == nil:
        fill_char = " "
    let words = split(text, " ")
    if len(words) == 0:
        return ""
    if len(words) == 1:
        let result = words[0]
        let remaining = width - rich.measure.measure_text(result)
        if remaining > 0:
            for i in range(remaining):
                result = result + fill_char
        return result
    let total_chars = 0
    for i in range(len(words)):
        total_chars = total_chars + rich.measure.measure_text(words[i])
    let total_gaps = len(words) - 1
    let spaces_needed = width - total_chars
    if spaces_needed <= total_gaps:
        # Not enough space to justify
        let result = ""
        for i in range(len(words)):
            if i > 0:
                result = result + fill_char
            result = result + words[i]
        let remaining = width - rich.measure.measure_text(result)
        if remaining > 0:
            for i in range(remaining):
                result = result + fill_char
        return result
    let spaces_per_gap = spaces_needed / total_gaps
    spaces_per_gap = spaces_per_gap | 0
    let extra_spaces = spaces_needed - spaces_per_gap * total_gaps
    let result = ""
    for i in range(len(words)):
        if i > 0:
            let this_gap = spaces_per_gap
            if i <= extra_spaces:
                this_gap = this_gap + 1
            for j in range(this_gap):
                result = result + fill_char
        result = result + words[i]
    return result

# Align a single line with a given alignment
proc align_line(text, alignment, width):
    return align(text, alignment, width, " ")

# Get align value from string
proc get_align(name):
    if name == "left":
        return ALIGN_LEFT
    if name == "center" or name == "centre":
        return ALIGN_CENTER
    if name == "right":
        return ALIGN_RIGHT
    if name == "justify":
        return ALIGN_JUSTIFY
    return ALIGN_LEFT

# Detect text alignment from left/right positions
proc detect_alignment(text, start, end_idx):
    let visible_text = rich.measure.strip_ansi(text)
    if start > 0 and end_idx < len(visible_text):
        return ALIGN_CENTER
    if end_idx == len(visible_text):
        return ALIGN_RIGHT
    return ALIGN_LEFT
