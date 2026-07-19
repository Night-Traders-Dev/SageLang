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
    style["color"] = nil
    if color != nil:
        style["color"] = color
    style["bgcolor"] = nil
    if bgcolor != nil:
        style["bgcolor"] = bgcolor
    style["bold"] = false
    if bold != nil:
        style["bold"] = bold
    style["dim"] = false
    if dim != nil:
        style["dim"] = dim
    style["italic"] = false
    if italic != nil:
        style["italic"] = italic
    style["underline"] = false
    if underline != nil:
        style["underline"] = underline
    style["blink"] = false
    if blink != nil:
        style["blink"] = blink
    style["reverse"] = false
    if reverse != nil:
        style["reverse"] = reverse
    style["strike"] = false
    if strike != nil:
        style["strike"] = strike
    style["link"] = nil
    if link != nil:
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
        else:
            if part == "not" and i + 1 < len(parts) and lower(parts[i + 1]) == "bold":
                s["bold"] = false
                i = i + 1
            else:
                                if part == "dim":
                                    s["dim"] = true
                                else:
                                    if part == "not" and i + 1 < len(parts) and lower(parts[i + 1]) == "dim":
                                        s["dim"] = false
                                        i = i + 1
                                    else:
                                        if part == "italic":
                                            s["italic"] = true
                                        else:
                                            if part == "not" and i + 1 < len(parts) and lower(parts[i + 1]) == "italic":
                                                s["italic"] = false
                                                i = i + 1
                                            else:
                                                if part == "underline":
                                                    s["underline"] = true
                                                else:
                                                    if part == "not" and i + 1 < len(parts) and lower(parts[i + 1]) == "underline":
                                                        s["underline"] = false
                                                        i = i + 1
                                                    else:
                                                        if part == "blink":
                                                            s["blink"] = true
                                                        else:
                                                            if part == "not" and i + 1 < len(parts) and lower(parts[i + 1]) == "blink":
                                                                s["blink"] = false
                                                                i = i + 1
                                                            else:
                                                                if part == "reverse":
                                                                    s["reverse"] = true
                                                                else:
                                                                    if part == "not" and i + 1 < len(parts) and lower(parts[i + 1]) == "reverse":
                                                                        s["reverse"] = false
                                                                        i = i + 1
                                                                    else:
                                                                        if part == "strike":
                                                                            s["strike"] = true
                                                                        else:
                                                                            if part == "not" and i + 1 < len(parts) and lower(parts[i + 1]) == "strike":
                                                                                s["strike"] = false
                                                                                i = i + 1
                                                                            else:
                                                                                if part == "link":
                                                                                    if i + 1 < len(parts):
                                                                                        s["link"] = parts[i + 1]
                                                                                        i = i + 1
                                                                                else:
                                                                                    if part == "default" or part == "none":
                                                                                        s["color"] = nil
                                                                                        s["bgcolor"] = nil
                                                                                    else:
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
