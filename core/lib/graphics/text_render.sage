gc_disable()
# text_render.sage - Bitmap font text rendering
# Generates line-segment geometry for debug text overlay
# No font atlas needed - uses hardcoded 5x7 pixel font glyphs

import gpu

# 5x7 bitmap font for ASCII 32-126
# Each character is a list of line segments: [x1,y1, x2,y2, ...]

proc get_char_lines(ch):
    let lines = []
    # Normalized 0-1 coordinates for each character
    if ch == "A":
        return [0,0, 0,1, 0,1, 0.5,1, 0.5,1, 1,1, 1,1, 1,0, 0,0.5, 1,0.5]
    if ch == "B":
        return [0,0, 0,1, 0,1, 0.7,1, 0.7,1, 0.7,0.5, 0.7,0.5, 0,0.5, 0,0, 0.7,0, 0.7,0, 0.7,0.5]
    if ch == "C":
        return [0.8,0, 0,0, 0,0, 0,1, 0,1, 0.8,1]
    if ch == "D":
        return [0,0, 0,1, 0,1, 0.6,1, 0.6,1, 0.8,0.5, 0.8,0.5, 0.6,0, 0.6,0, 0,0]
    if ch == "E":
        return [0.8,0, 0,0, 0,0, 0,1, 0,1, 0.8,1, 0,0.5, 0.6,0.5]
    if ch == "F":
        return [0,0, 0,1, 0,1, 0.8,1, 0,0.5, 0.6,0.5]
    if ch == "G":
        return [0.8,1, 0,1, 0,1, 0,0, 0,0, 0.8,0, 0.8,0, 0.8,0.5, 0.8,0.5, 0.4,0.5]
    if ch == "H":
        return [0,0, 0,1, 1,0, 1,1, 0,0.5, 1,0.5]
    if ch == "I":
        return [0.5,0, 0.5,1, 0.2,1, 0.8,1, 0.2,0, 0.8,0]
    if ch == "K":
        return [0,0, 0,1, 0,0.5, 0.8,1, 0,0.5, 0.8,0]
    if ch == "L":
        return [0,1, 0,0, 0,0, 0.8,0]
    if ch == "M":
        return [0,0, 0,1, 0,1, 0.5,0.5, 0.5,0.5, 1,1, 1,1, 1,0]
    if ch == "N":
        return [0,0, 0,1, 0,1, 1,0, 1,0, 1,1]
    if ch == "O":
        return [0,0, 0.8,0, 0.8,0, 0.8,1, 0.8,1, 0,1, 0,1, 0,0]
    if ch == "P":
        return [0,0, 0,1, 0,1, 0.7,1, 0.7,1, 0.7,0.5, 0.7,0.5, 0,0.5]
    if ch == "R":
        return [0,0, 0,1, 0,1, 0.7,1, 0.7,1, 0.7,0.5, 0.7,0.5, 0,0.5, 0,0.5, 0.7,0]
    if ch == "S":
        return [0.8,1, 0,1, 0,1, 0,0.5, 0,0.5, 0.8,0.5, 0.8,0.5, 0.8,0, 0.8,0, 0,0]
    if ch == "T":
        return [0,1, 1,1, 0.5,1, 0.5,0]
    if ch == "U":
        return [0,1, 0,0, 0,0, 0.8,0, 0.8,0, 0.8,1]
    if ch == "V":
        return [0,1, 0.5,0, 0.5,0, 1,1]
    if ch == "W":
        return [0,1, 0.2,0, 0.2,0, 0.5,0.5, 0.5,0.5, 0.8,0, 0.8,0, 1,1]
    if ch == "X":
        return [0,0, 1,1, 1,0, 0,1]
    if ch == "Y":
        return [0,1, 0.5,0.5, 1,1, 0.5,0.5, 0.5,0.5, 0.5,0]
    if ch == "Z":
        return [0,1, 1,1, 1,1, 0,0, 0,0, 1,0]
    if ch == "0":
        return [0,0, 0.8,0, 0.8,0, 0.8,1, 0.8,1, 0,1, 0,1, 0,0, 0,0, 0.8,1]
    if ch == "1":
        return [0.4,0, 0.4,1, 0.2,0.8, 0.4,1, 0.2,0, 0.6,0]
    if ch == "2":
        return [0,1, 0.8,1, 0.8,1, 0.8,0.5, 0.8,0.5, 0,0.5, 0,0.5, 0,0, 0,0, 0.8,0]
    if ch == "3":
        return [0,1, 0.8,1, 0.8,1, 0.8,0, 0.8,0, 0,0, 0,0.5, 0.8,0.5]
    if ch == "4":
        return [0,1, 0,0.5, 0,0.5, 0.8,0.5, 0.8,1, 0.8,0]
    if ch == "5":
        return [0.8,1, 0,1, 0,1, 0,0.5, 0,0.5, 0.8,0.5, 0.8,0.5, 0.8,0, 0.8,0, 0,0]
    if ch == "6":
        return [0.8,1, 0,1, 0,1, 0,0, 0,0, 0.8,0, 0.8,0, 0.8,0.5, 0.8,0.5, 0,0.5]
    if ch == "7":
        return [0,1, 0.8,1, 0.8,1, 0.3,0]
    if ch == "8":
        return [0,0, 0.8,0, 0.8,0, 0.8,1, 0.8,1, 0,1, 0,1, 0,0, 0,0.5, 0.8,0.5]
    if ch == "9":
        return [0,0, 0.8,0, 0.8,0, 0.8,1, 0.8,1, 0,1, 0,1, 0,0.5, 0,0.5, 0.8,0.5]
    if ch == ".":
        return [0.3,0.05, 0.5,0.05, 0.5,0.05, 0.5,0, 0.5,0, 0.3,0, 0.3,0, 0.3,0.05]
    if ch == ":":
        return [0.3,0.7, 0.5,0.7, 0.3,0.3, 0.5,0.3]
    if ch == "-":
        return [0.1,0.5, 0.7,0.5]
    if ch == "+":
        return [0.1,0.5, 0.7,0.5, 0.4,0.2, 0.4,0.8]
    if ch == "/":
        return [0,0, 0.8,1]
    if ch == "(":
        return [0.5,0, 0.2,0.3, 0.2,0.3, 0.2,0.7, 0.2,0.7, 0.5,1]
    if ch == ")":
        return [0.3,0, 0.6,0.3, 0.6,0.3, 0.6,0.7, 0.6,0.7, 0.3,1]
    if ch == "|":
        return [0.4,0, 0.4,1]
    if ch == " ":
        return []
    # Unknown char: draw a box
    return [0,0, 0.6,0, 0.6,0, 0.6,1, 0.6,1, 0,1, 0,1, 0,0]

# Build line vertices for a string
# Returns flat float array for LINE_LIST topology: [x1,y1, x2,y2, ...]
# Coordinates in screen space: (0,0) = top-left, units = pixels
proc build_text_lines(text, x, y, char_width, char_height):
    let verts = []
    let cx = x
    let ci = 0
    while ci < len(text):
        let ch = text[ci]
        let lines = get_char_lines(ch)
        let li = 0
        while li < len(lines):
            if li + 3 < len(lines):
                # Line segment
                push(verts, cx + lines[li] * char_width)
                push(verts, y + (1.0 - lines[li + 1]) * char_height)
                push(verts, cx + lines[li + 2] * char_width)
                push(verts, y + (1.0 - lines[li + 3]) * char_height)
            li = li + 4
        cx = cx + char_width * 1.2
        ci = ci + 1
    return verts

# Convert pixel coordinates to NDC (-1 to 1)
proc screen_to_ndc(verts, screen_w, screen_h):
    let result = []
    let i = 0
    while i < len(verts):
        push(result, verts[i] / screen_w * 2.0 - 1.0)
        push(result, verts[i + 1] / screen_h * 2.0 - 1.0)
        i = i + 2
    return result

# Vertex count (number of line endpoints)
proc text_vertex_count(verts):
    return len(verts) / 2
