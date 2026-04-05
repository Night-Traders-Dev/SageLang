gc_disable()
# SageLang Code Formatter (self-hosted port)
#
# Rules:
#   1. Normalize indentation to multiples of indent_width spaces
#   2. Remove trailing whitespace
#   3. Single blank line between top-level proc/class definitions
#   4. No more than max_blank_lines consecutive blank lines
#   5. File ends with exactly one newline
#   6. Normalize spaces around operators (outside strings)
#   7. Normalize spaces after commas (outside strings)
#   8. Remove spaces before colons at end of block headers
#   9. Ensure space after # in comments (preserve #! shebangs)
import io

let INDENT_WIDTH = 4
let MAX_BLANK_LINES = 2

# Check if a stripped line starts a top-level definition
proc is_toplevel_def(stripped):
    if startswith(stripped, "proc "):
        return true
    if startswith(stripped, "async proc "):
        return true
    if startswith(stripped, "class "):
        return true
    return false

# Check if a line is a block header ending with :
proc is_block_header(stripped):
    let slen = len(stripped)
    if slen == 0:
        return false
    # Find trailing colon (skipping trailing spaces)
    let tail = slen - 1
    let found_colon = false
    while tail >= 0:
        let ch = stripped[tail]
        if ch == ":":
            found_colon = true
            break
        if ch != " ":
            break
        tail = tail - 1
    if not found_colon:
        return false
    # Check block keywords
    let kws = ["proc ", "async proc ", "class ", "if ", "elif ", "else:", "for ", "while ", "try:", "catch ", "finally:", "match ", "case "]
    for kw in kws:
        if startswith(stripped, kw):
            return true
    if stripped == "else:":
        return true
    if stripped == "try:":
        return true
    if stripped == "finally:":
        return true
    return false

# Check if character is alphanumeric or underscore
proc is_word_char(ch):
    let c = ord(ch)
    # a-z
    if c >= 97:
        if c <= 122:
            return true
    # A-Z
    if c >= 65:
        if c <= 90:
            return true
    # 0-9
    if c >= 48:
        if c <= 57:
            return true
    if ch == "_":
        return true
    return false

# Check if two-char operator at position
proc is_two_char_op(s, pos):
    if pos + 1 >= len(s):
        return false
    let c0 = s[pos]
    let c1 = s[pos + 1]
    if c0 == "=" and c1 == "=":
        return true
    if c0 == "!" and c1 == "=":
        return true
    if c0 == "<" and c1 == "=":
        return true
    if c0 == ">" and c1 == "=":
        return true
    if c0 == "+" and c1 == "=":
        return true
    if c0 == "-" and c1 == "=":
        return true
    if c0 == "*" and c1 == "=":
        return true
    if c0 == "/" and c1 == "=":
        return true
    return false

# Check if keyword operator at position
proc is_keyword_op_at(s, pos, kw):
    let slen = len(s)
    let kwlen = len(kw)
    if pos + kwlen > slen:
        return false
    # Check substring match
    for k in range(kwlen):
        if s[pos + k] != kw[k]:
            return false
    # Word boundary before
    if pos > 0:
        if is_word_char(s[pos - 1]):
            return false
    # Word boundary after
    if pos + kwlen < slen:
        if is_word_char(s[pos + kwlen]):
            return false
    return true

# Normalize operators in a line (preserving strings)
proc normalize_operators(content):
    let clen = len(content)
    let out = []
    let in_string = ""
    let i = 0
    while i < clen:
        let c = content[i]
        # Track string state
        if in_string == "":
            if c == chr(34) or c == chr(39):
                in_string = c
                push(out, c)
                i = i + 1
                continue
        if in_string != "":
            push(out, c)
            if c == in_string:
                in_string = ""
            i = i + 1
            continue
        # Comment: pass through rest
        if c == "#":
            while i < clen:
                push(out, content[i])
                i = i + 1
            break
        # Keyword operators: and, or, not
        if is_keyword_op_at(content, i, "and"):
            if len(out) > 0 and out[len(out) - 1] != " ":
                push(out, " ")
            push(out, "a")
            push(out, "n")
            push(out, "d")
            i = i + 3
            if i < clen and content[i] != " ":
                push(out, " ")
            continue
        if is_keyword_op_at(content, i, "or"):
            if len(out) > 0 and out[len(out) - 1] != " ":
                push(out, " ")
            push(out, "o")
            push(out, "r")
            i = i + 2
            if i < clen and content[i] != " ":
                push(out, " ")
            continue
        if is_keyword_op_at(content, i, "not"):
            if len(out) > 0 and out[len(out) - 1] != " ":
                push(out, " ")
            push(out, "n")
            push(out, "o")
            push(out, "t")
            i = i + 3
            if i < clen and content[i] != " ":
                push(out, " ")
            continue
        # Two-char operators
        if is_two_char_op(content, i):
            # Remove trailing spaces
            while len(out) > 0 and out[len(out) - 1] == " ":
                pop(out)
            push(out, " ")
            push(out, content[i])
            push(out, content[i + 1])
            push(out, " ")
            i = i + 2
            while i < clen and content[i] == " ":
                i = i + 1
            continue
        # Single = assignment
        if c == "=":
            let next_eq = false
            if i + 1 < clen:
                if content[i + 1] == "=":
                    next_eq = true
            if not next_eq:
                let prev_ok = true
                if i > 0:
                    let pc = content[i - 1]
                    if pc == "!" or pc == "<" or pc == ">" or pc == "+" or pc == "-" or pc == "*" or pc == "/":
                        prev_ok = false
                if prev_ok:
                    while len(out) > 0 and out[len(out) - 1] == " ":
                        pop(out)
                    push(out, " ")
                    push(out, "=")
                    push(out, " ")
                    i = i + 1
                    while i < clen and content[i] == " ":
                        i = i + 1
                    continue
        # Single < >
        if c == "<" or c == ">":
            let next_eq2 = false
            if i + 1 < clen:
                if content[i + 1] == "=":
                    next_eq2 = true
            if not next_eq2:
                while len(out) > 0 and out[len(out) - 1] == " ":
                    pop(out)
                push(out, " ")
                push(out, c)
                push(out, " ")
                i = i + 1
                while i < clen and content[i] == " ":
                    i = i + 1
                continue
        # Arithmetic operators
        if c == "+" or c == "-" or c == "*" or c == "/" or c == "%":
            let next_eq3 = false
            if i + 1 < clen:
                if content[i + 1] == "=":
                    next_eq3 = true
            if not next_eq3:
                # Check unary
                let is_unary = false
                if c == "-" or c == "+":
                    let back = len(out)
                    while back > 0 and out[back - 1] == " ":
                        back = back - 1
                    if back == 0:
                        is_unary = true
                    else:
                        let prev2 = out[back - 1]
                        if prev2 == "(" or prev2 == "[" or prev2 == "," or prev2 == "=" or prev2 == "<" or prev2 == ">":
                            is_unary = true
                        if prev2 == "+" or prev2 == "-" or prev2 == "*" or prev2 == "/" or prev2 == "%" or prev2 == ":":
                            is_unary = true
                if is_unary:
                    push(out, c)
                    i = i + 1
                    continue
                # Binary operator
                while len(out) > 0 and out[len(out) - 1] == " ":
                    pop(out)
                push(out, " ")
                push(out, c)
                push(out, " ")
                i = i + 1
                while i < clen and content[i] == " ":
                    i = i + 1
                continue
        # Comma normalization
        if c == ",":
            push(out, ",")
            i = i + 1
            while i < clen and content[i] == " ":
                i = i + 1
            if i < clen:
                push(out, " ")
            continue
        # Collapse multiple spaces
        if c == " ":
            push(out, " ")
            i = i + 1
            while i < clen and content[i] == " ":
                i = i + 1
            continue
        # Default
        push(out, c)
        i = i + 1
    return join(out, "")

# Normalize comment: ensure space after #
proc normalize_comment(line):
    let result = []
    let in_str = ""
    let llen = len(line)
    let i = 0
    while i < llen:
        let c = line[i]
        if in_str == "":
            if c == chr(34) or c == chr(39):
                in_str = c
                push(result, c)
                i = i + 1
                continue
        if in_str != "":
            push(result, c)
            if c == in_str:
                in_str = ""
            i = i + 1
            continue
        if c == "#":
            push(result, "#")
            i = i + 1
            # Preserve shebangs
            if i < llen and line[i] == "!":
                while i < llen:
                    push(result, line[i])
                    i = i + 1
                return join(result, "")
            # Ensure space after #
            if i < llen and line[i] != " ":
                push(result, " ")
            while i < llen:
                push(result, line[i])
                i = i + 1
            return join(result, "")
        push(result, c)
        i = i + 1
    return join(result, "")

# Remove space before colon at end of block header
proc strip_colon_space(line):
    let llen = len(line)
    if llen == 0:
        return line
    if line[llen - 1] != ":":
        return line
    let colon_pos = llen - 1
    let space_start = colon_pos
    while space_start > 0 and line[space_start - 1] == " ":
        space_start = space_start - 1
    if space_start == colon_pos:
        return line
    # Rebuild without spaces before colon
    let parts = []
    for j in range(space_start):
        push(parts, line[j])
    push(parts, ":")
    return join(parts, "")

# Make a string of n spaces
proc spaces(n):
    let result = []
    for i in range(n):
        push(result, " ")
    return join(result, "")

# Split source into lines
proc split_lines(source):
    return split(source, chr(10))

# Strip trailing whitespace from a string
proc rstrip(s):
    let slen = len(s)
    let stop = slen
    while stop > 0:
        let ch = s[stop - 1]
        if ch != " " and ch != chr(9) and ch != chr(13):
            break
        stop = stop - 1
    if stop == slen:
        return s
    let result = []
    for i in range(stop):
        push(result, s[i])
    return join(result, "")

# Count leading whitespace
proc count_leading(line):
    let count = 0
    let i = 0
    let llen = len(line)
    while i < llen:
        let ch = line[i]
        if ch == " ":
            count = count + 1
            i = i + 1
            continue
        if ch == chr(9):
            count = count + INDENT_WIDTH
            i = i + 1
            continue
        break
    return count

# Get content after leading whitespace
proc strip_leading(line):
    let i = 0
    let llen = len(line)
    while i < llen:
        if line[i] != " " and line[i] != chr(9):
            break
        i = i + 1
    let result = []
    while i < llen:
        push(result, line[i])
        i = i + 1
    return join(result, "")

# Main formatting function
proc format_source(source):
    let lines = split_lines(source)
    let result = []
    let consecutive_blanks = 0
    let prev_indent_level = -1
    let nl = chr(10)
    for i in range(len(lines)):
        let raw = lines[i]
        let leading = count_leading(raw)
        let content = rstrip(strip_leading(raw))
        # Handle blank lines
        if len(content) == 0:
            consecutive_blanks = consecutive_blanks + 1
            if consecutive_blanks <= MAX_BLANK_LINES:
                push(result, "")
            continue
        # Non-blank line
        let indent_level = leading / INDENT_WIDTH
        let is_top_def = false
        if indent_level == 0:
            is_top_def = is_toplevel_def(content)
        # Insert blank line before top-level def if needed
        if is_top_def and i > 0 and consecutive_blanks == 0 and prev_indent_level >= 0:
            push(result, "")
        consecutive_blanks = 0
        # Normalize indentation
        let norm_indent = indent_level * INDENT_WIDTH
        # Process content
        let processed = normalize_operators(content)
        processed = normalize_comment(processed)
        # Strip space before colon on block headers
        if is_block_header(content):
            processed = strip_colon_space(processed)
        # Build formatted line
        push(result, spaces(norm_indent) + processed)
        prev_indent_level = indent_level
    # Remove trailing blank lines
    while len(result) > 1 and result[len(result) - 1] == "":
        pop(result)
    # Ensure file ends with newline
    push(result, "")
    return join(result, nl)

# Format a file in-place
proc format_file(path):
    let source = io.read(path)
    if source == nil:
        print "sage fmt: cannot open " + chr(39) + path + chr(39)
        return false
    let formatted = format_source(source)
    io.write(path, formatted)
    return true

# Check if a file needs formatting (returns true if already formatted)
proc check_file(path):
    let source = io.read(path)
    if source == nil:
        print "sage fmt: cannot open " + chr(39) + path + chr(39)
        return false
    let formatted = format_source(source)
    return source == formatted
