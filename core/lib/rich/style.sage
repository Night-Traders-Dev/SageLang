gc_disable()
import rich.color as color

# Text style definition and rendering

let RESET = chr(27) + "[0m"
let BOLD = chr(27) + "[1m"
let DIM = chr(27) + "[2m"
let ITALIC = chr(27) + "[3m"
let UNDERLINE = chr(27) + "[4m"
let BLINK = chr(27) + "[5m"
let REVERSE = chr(27) + "[7m"
let STRIKE = chr(27) + "[9m"
let NO_BOLD = chr(27) + "[22m"
let NO_ITALIC = chr(27) + "[23m"
let NO_UNDERLINE = chr(27) + "[24m"
let NO_BLINK = chr(27) + "[25m"
let NO_REVERSE = chr(27) + "[27m"
let NO_STRIKE = chr(27) + "[29m"

# Style flags
let STYLE_BOLD = 1
let STYLE_DIM = 2
let STYLE_ITALIC = 4
let STYLE_UNDERLINE = 8
let STYLE_BLINK = 16
let STYLE_REVERSE = 32
let STYLE_STRIKE = 64

# Create a style object
proc Style(color, bgcolor, bold, dim, italic, underline, blink, reverse, strike, link):
    let style = {}
    style["color"] = color
    style["bgcolor"] = bgcolor
    style["bold"] = bold or false
    style["dim"] = dim or false
    style["italic"] = italic or false
    style["underline"] = underline or false
    style["blink"] = blink or false
    style["reverse"] = reverse or false
    style["strike"] = strike or false
    style["link"] = link
    return style

proc style_default():
    return Style(nil, nil, false, false, false, false, false, false, false, nil)

# Parse a style string like "bold red on blue"
proc parse_style(style_str):
    if style_str == nil or style_str == "":
        return style_default()
    let s = style_default()
    let parts = split(lower(style_str), " ")
    let i = 0
    let expecting_on = false
    while i < len(parts):
        let part = parts[i]
        if part == "":
            i = i + 1
            continue
        if part == "on":
            expecting_on = true
            i = i + 1
            continue
        if part == "bold":
            s["bold"] = true
        elif part == "dim":
            s["dim"] = true
        elif part == "italic":
            s["italic"] = true
        elif part == "underline":
            s["underline"] = true
        elif part == "blink":
            s["blink"] = true
        elif part == "reverse":
            s["reverse"] = true
        elif part == "strike":
            s["strike"] = true
        elif part == "not" and i + 1 < len(parts):
            let flag = lower(parts[i + 1])
            if flag == "bold":
                s["bold"] = false
            elif flag == "dim":
                s["dim"] = false
            elif flag == "italic":
                s["italic"] = false
            elif flag == "underline":
                s["underline"] = false
            elif flag == "blink":
                s["blink"] = false
            elif flag == "reverse":
                s["reverse"] = false
            elif flag == "strike":
                s["strike"] = false
            i = i + 1
        elif part == "link":
            if i + 1 < len(parts):
                s["link"] = parts[i + 1]
                i = i + 1
        elif part == "default" or part == "none":
            s["color"] = nil
            s["bgcolor"] = nil
        else:
            let c = color.parse_color(part)
            if c != nil:
                if expecting_on:
                    s["bgcolor"] = c
                    expecting_on = false
                else:
                    s["color"] = c
        i = i + 1
    return s

# Generate ANSI escape sequence for a style
proc style_ansi_open(style):
    if style == nil:
        return ""
    let parts = []
    if style["bold"]:
        push(parts, BOLD)
    if style["dim"]:
        push(parts, DIM)
    if style["italic"]:
        push(parts, ITALIC)
    if style["underline"]:
        push(parts, UNDERLINE)
    if style["blink"]:
        push(parts, BLINK)
    if style["reverse"]:
        push(parts, REVERSE)
    if style["strike"]:
        push(parts, STRIKE)
    if style["color"] != nil:
        push(parts, color.color_ansi_escape(style["color"], false))
    if style["bgcolor"] != nil:
        push(parts, color.color_ansi_escape(style["bgcolor"], true))
    if len(parts) == 0:
        return ""
    return join(parts, "")

proc style_ansi_close(style):
    if style == nil:
        return ""
    return RESET

# Render a string with a style applied
proc render_styled(text, style):
    if style == nil:
        return text
    let open_seq = style_ansi_open(style)
    if open_seq == "":
        return text
    return open_seq + text + RESET

# Check if a style is the default/empty style
proc is_default_style(style):
    if style == nil:
        return true
    if style["color"] != nil:
        return false
    if style["bgcolor"] != nil:
        return false
    if style["bold"]:
        return false
    if style["italic"]:
        return false
    if style["underline"]:
        return false
    if style["blink"]:
        return false
    if style["reverse"]:
        return false
    if style["strike"]:
        return false
    return true

# Merge two styles: base with override on top
proc merge_styles(base, override):
    if override == nil:
        return base
    if base == nil:
        return override
    let result = {}
    result["color"] = base["color"]
    if dict_has(override, "color") and override["color"] != nil:
        result["color"] = override["color"]
    result["bgcolor"] = base["bgcolor"]
    if dict_has(override, "bgcolor") and override["bgcolor"] != nil:
        result["bgcolor"] = override["bgcolor"]
    result["bold"] = base["bold"]
    if dict_has(override, "bold") and override["bold"] != base["bold"]:
        result["bold"] = override["bold"]
    result["dim"] = base["dim"]
    if dict_has(override, "dim") and override["dim"] != base["dim"]:
        result["dim"] = override["dim"]
    result["italic"] = base["italic"]
    if dict_has(override, "italic") and override["italic"] != base["italic"]:
        result["italic"] = override["italic"]
    result["underline"] = base["underline"]
    if dict_has(override, "underline") and override["underline"] != base["underline"]:
        result["underline"] = override["underline"]
    result["blink"] = base["blink"]
    if dict_has(override, "blink") and override["blink"] != base["blink"]:
        result["blink"] = override["blink"]
    result["reverse"] = base["reverse"]
    if dict_has(override, "reverse") and override["reverse"] != base["reverse"]:
        result["reverse"] = override["reverse"]
    result["strike"] = base["strike"]
    if dict_has(override, "strike") and override["strike"] != base["strike"]:
        result["strike"] = override["strike"]
    result["link"] = base["link"]
    if dict_has(override, "link") and override["link"] != nil:
        result["link"] = override["link"]
    return result

# Get a null style (empty)
proc null_style():
    return style_default()

# Style without any color
proc no_style():
    return style_default()
