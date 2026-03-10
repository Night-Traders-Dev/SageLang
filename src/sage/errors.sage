# -----------------------------------------
# errors.sage - Rich error reporting module
# Rust/Elm-style error messages with source context
# -----------------------------------------

let NL = chr(10)

# -----------------------------------------
# Split source text into an array of lines
# -----------------------------------------
proc split_lines(source):
    let lines = []
    let current = ""
    let i = 0
    let slen = len(source)
    while i < slen:
        let c = source[i]
        if c == chr(10):
            push(lines, current)
            current = ""
        else:
            current = current + c
        i = i + 1
    push(lines, current)
    return lines

# -----------------------------------------
# make_error_context - create a dict-based error context
# Avoids class methods that can't see module-level procs
# -----------------------------------------
proc make_error_context(source, filename):
    let ctx = {}
    ctx["source"] = source
    ctx["filename"] = filename
    ctx["lines"] = split_lines(source)
    return ctx

# For backward compatibility - ErrorContext class that works
# by pre-splitting lines before storing
class ErrorContext:
    proc init(source, filename):
        self.source = source
        self.filename = filename
        # Lines must be passed in or set externally
        self.lines = []

# -----------------------------------------
# get_line_text - return text of a 1-based line
# Works with both dict-based ctx and class-based ctx
# -----------------------------------------
proc get_line_text(ctx, line_num):
    let lines = nil
    if type(ctx) == "dict":
        lines = ctx["lines"]
    else:
        lines = ctx.lines
    if line_num < 1:
        return ""
    if line_num > len(lines):
        return ""
    return lines[line_num - 1]

# -----------------------------------------
# get_filename - get filename from ctx (dict or class)
# -----------------------------------------
proc get_filename(ctx):
    if type(ctx) == "dict":
        return ctx["filename"]
    return ctx.filename

# -----------------------------------------
# repeat_char - return a string of n copies of ch
# -----------------------------------------
proc repeat_char(ch, n):
    let result = ""
    let i = 0
    while i < n:
        result = result + ch
        i = i + 1
    return result

# -----------------------------------------
# make_pointer - build pointer string for col/length
# col is 0-based, length >= 1 means range
# -----------------------------------------
proc make_pointer(col, length):
    let padding = ""
    if col > 0:
        padding = repeat_char(" ", col)
    if length > 1:
        return padding + repeat_char("~", length)
    return padding + "^"

# -----------------------------------------
# int_to_str - convert number to string
# -----------------------------------------
proc int_to_str(n):
    return str(n)

# -----------------------------------------
# digit_count - number of digits in a positive int
# -----------------------------------------
proc digit_count(n):
    if n < 10:
        return 1
    if n < 100:
        return 2
    if n < 1000:
        return 3
    if n < 10000:
        return 4
    return 5

# -----------------------------------------
# pad_left - left-pad a string to given width
# -----------------------------------------
proc pad_left(s, width):
    let slen = len(s)
    if slen >= width:
        return s
    return repeat_char(" ", width - slen) + s

# -----------------------------------------
# format_error - main error formatting function
#
# ctx: dict from make_error_context or ErrorContext
# line: 1-based line number
# col: 0-based column (-1 if unknown)
# kind: "Error", "Warning", or "Note"
# message: the error message text
# hint: optional hint string (nil for none)
# -----------------------------------------
proc format_error(ctx, line, col, kind, message, hint):
    return format_error_range(ctx, line, col, 1, kind, message, hint)

# -----------------------------------------
# format_error_range - error with range underline
# -----------------------------------------
proc format_error_range(ctx, line, col, length, kind, message, hint):
    let out = ""
    let fname = get_filename(ctx)

    # Header line: "Error: message"
    out = out + kind + ": " + message + NL

    # Location line: "  --> filename:line:col"
    let loc = "  --> " + fname + ":" + int_to_str(line)
    if col >= 0:
        loc = loc + ":" + int_to_str(col + 1)
    out = out + loc + NL

    # Figure out gutter width from line number
    let gutter_w = digit_count(line)
    if gutter_w < 2:
        gutter_w = 2
    let blank_gutter = repeat_char(" ", gutter_w)

    # Blank separator
    out = out + blank_gutter + " |" + NL

    # Source line
    let line_text = get_line_text(ctx, line)
    let line_str = pad_left(int_to_str(line), gutter_w)
    out = out + line_str + " | " + line_text + NL

    # Pointer line
    if col >= 0:
        let pointer = make_pointer(col, length)
        out = out + blank_gutter + " | " + pointer + NL
    else:
        out = out + blank_gutter + " |" + NL

    # Hint line
    if hint != nil:
        out = out + blank_gutter + " |" + NL
        out = out + blank_gutter + " = hint: " + hint + NL

    return out

# -----------------------------------------
# format_type_error - convenience for type mismatches
# -----------------------------------------
proc format_type_error(ctx, line, expected, got, hint):
    let msg = "Type mismatch: expected " + expected + ", got " + got
    return format_error(ctx, line, -1, "Error", msg, hint)

# -----------------------------------------
# format_undefined_error - undefined variable/name
# -----------------------------------------
proc format_undefined_error(ctx, line, name, suggestions):
    let msg = "Undefined name: " + chr(39) + name + chr(39)
    let h = nil
    if len(suggestions) > 0:
        h = "Did you mean "
        let i = 0
        while i < len(suggestions):
            if i > 0:
                if i == len(suggestions) - 1:
                    h = h + " or "
                else:
                    h = h + ", "
            h = h + chr(39) + suggestions[i] + chr(39)
            i = i + 1
        h = h + "?"
    return format_error(ctx, line, -1, "Error", msg, h)
