gc_disable()
import rich.color

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
    style["color"] = color if color != nil else nil
    style["bgcolor"] = bgcolor if bgcolor != nil else nil
    style["bold"] = bold if bold != nil else false
    style["dim"] = dim if dim != nil else false
    style["italic"] = italic if italic != nil else false
    style["underline"] = underline if underline != nil else false
    style["blink"] = blink if blink != nil else false
    style["reverse"] = reverse if reverse != nil else false
    style["strike"] = strike if strike != nil else false
    style["link"] = link if link != nil else nil
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
    let on_next = false
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
        else if part == "not" and i + 1 < len(parts) and lower(parts[i + 1]) == "bold":
            s["bold"] = false
            i = i + 1
        else if part == "dim":
            s["dim"] = true
        else if part == "italic":
            s["italic"] = true
        else if part == "not" and i + 1 < len(parts) and lower(parts[i + 1]) == "italic":
            s["italic"] = false
            i = i + 1
        else if part == "underline":
            s["underline"] = true
        else if part == "blink":
            s["blink"] = true
        else if part == "reverse":
            s["reverse"] = true
        else if part == "strike":
            s["strike"] = true
        else if part == "link":
            if i + 1 < len(parts):
                s["link"] = parts[i + 1]
                i = i + 1
        else if part == "default" or part == "none":
            s["color"] = nil
            s["bgcolor"] = nil
        else:
            # Try to parse as color
            let c = rich.color.parse_color(part)
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
    let result = ""
    if style["bold"]:
        result = result + BOLD
    if style["dim"]:
        result = result + DIM
    if style["italic"]:
        result = result + ITALIC
    if style["underline"]:
        result = result + UNDERLINE
    if style["blink"]:
        result = result + BLINK
    if style["reverse"]:
        result = result + REVERSE
    if style["strike"]:
        result = result + STRIKE
    if style["color"] != nil:
        result = result + rich.color.color_ansi_escape(style["color"], false)
    if style["bgcolor"] != nil:
        result = result + rich.color.color_ansi_escape(style["bgcolor"], true)
    return result

proc style_ansi_close(style):
    if style == nil:
        return ""
    let result = RESET
    # Re-apply surrounding style if any (for nested styles, handled by caller)
    return result

# Render a string with a style applied
proc render_styled(text, style):
    if style == nil:
        return text
    return style_ansi_open(style) + text + style_ansi_close(style)

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
    result["color"] = override["color"] if override["color"] != nil else base["color"]
    result["bgcolor"] = override["bgcolor"] if override["bgcolor"] != nil else base["bgcolor"]
    result["bold"] = override["bold"] if override["bold"] != false else base["bold"]
    result["dim"] = override["dim"] if override["dim"] != false else base["dim"]
    result["italic"] = override["italic"] if override["italic"] != false else base["italic"]
    result["underline"] = override["underline"] if override["underline"] != false else base["underline"]
    result["blink"] = override["blink"] if override["blink"] != false else base["blink"]
    result["reverse"] = override["reverse"] if override["reverse"] != false else base["reverse"]
    result["strike"] = override["strike"] if override["strike"] != false else base["strike"]
    result["link"] = override["link"] if override["link"] != nil else base["link"]
    return result

# Get a null style (empty)
proc null_style():
    return style_default()

# Style without any color
proc no_style():
    return style_default()
