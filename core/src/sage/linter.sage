gc_disable()
# SageLang Linter (self-hosted port)
#
# Rules:
#   E001: Indentation not multiple of 4
#   E002: Mixed tabs and spaces
#   E003: Line too long (>120 chars)
#   W001: Unused variables
#   W002: Shadowed variables
#   W003: Unreachable code after return/break/continue
#   W004: Empty block
#   W005: Bare catch without variable
#   S001: Proc name not snake_case
#   S002: Class name not PascalCase
#   S003: Missing docstring for top-level proc
#   S004: Trailing semicolons
#   S005: Multiple statements on one line
import io

# Severity constants
let SEV_ERROR = "error"
let SEV_WARNING = "warning"
let SEV_STYLE = "style"

# Create a lint message
proc make_msg(line, col, severity, rule, message):
    let msg = {}
    msg["line"] = line
    msg["col"] = col
    msg["severity"] = severity
    msg["rule"] = rule
    msg["message"] = message
    return msg

# Helper: check if character is lowercase letter
proc is_lower(ch):
    let c = ord(ch)
    return c >= 97 and c <= 122

# Helper: check if character is uppercase letter
proc is_upper(ch):
    let c = ord(ch)
    return c >= 65 and c <= 90

# Helper: check if character is a digit
proc is_digit(ch):
    let c = ord(ch)
    return c >= 48 and c <= 57

# Helper: check if character is alphanumeric or underscore
proc is_word_char(ch):
    return is_lower(ch) or is_upper(ch) or is_digit(ch) or ch == "_"

# Check if name is snake_case
proc is_snake_case(name):
    if len(name) == 0:
        return true
    for i in range(len(name)):
        let ch = name[i]
        if not is_lower(ch) and not is_digit(ch) and ch != "_":
            return false
    return true

# Check if name is PascalCase
proc is_pascal_case(name):
    if len(name) == 0:
        return false
    return is_upper(name[0])

# Extract identifier after a position in a string
proc extract_ident_after(buf, start):
    let blen = len(buf)
    let i = start
    while i < blen and (buf[i] == " " or buf[i] == chr(9)):
        i = i + 1
    if i >= blen:
        return nil
    if not is_lower(buf[i]) and not is_upper(buf[i]) and buf[i] != "_":
        return nil
    let begin = i
    while i < blen and is_word_char(buf[i]):
        i = i + 1
    let chars = []
    for j in range(begin, i):
        push(chars, buf[j])
    return join(chars, "")

# Measure indentation of a line
proc measure_indent(line):
    let width = 0
    let has_tab = false
    let has_space = false
    let llen = len(line)
    let i = 0
    while i < llen:
        let ch = line[i]
        if ch == " ":
            width = width + 1
            has_space = true
            i = i + 1
            continue
        if ch == chr(9):
            width = width + 4
            has_tab = true
            i = i + 1
            continue
        break
    let result = {}
    result["width"] = width
    result["has_tab"] = has_tab
    result["has_space"] = has_space
    return result

# Check if line is blank
proc is_blank_line(line):
    let llen = len(line)
    for i in range(llen):
        let ch = line[i]
        if ch != " " and ch != chr(9) and ch != chr(13):
            return false
    return true

# Get trimmed content of a line
proc trim_line(line):
    let llen = len(line)
    let start = 0
    while start < llen and (line[start] == " " or line[start] == chr(9)):
        start = start + 1
    let stop = llen
    while stop > start and (line[stop - 1] == " " or line[stop - 1] == chr(9) or line[stop - 1] == chr(13) or line[stop - 1] == chr(10)):
        stop = stop - 1
    let chars = []
    for i in range(start, stop):
        push(chars, line[i])
    return join(chars, "")

# Get line length (excluding newline)
proc line_length(line):
    let llen = len(line)
    while llen > 0 and (line[llen - 1] == chr(10) or line[llen - 1] == chr(13)):
        llen = llen - 1
    return llen

# Check if name appears as a word in a line
proc name_in_line(line, name):
    let llen = len(line)
    let nlen = len(name)
    for i in range(llen - nlen + 1):
        let found = true
        for j in range(nlen):
            if line[i + j] != name[j]:
                found = false
                break
        if found:
            let before_ok = true
            if i > 0:
                before_ok = not is_word_char(line[i - 1])
            let after_ok = true
            if i + nlen < llen:
                after_ok = not is_word_char(line[i + nlen])
            if before_ok and after_ok:
                return true
    return false

# Core linting function
proc lint_source(source):
    let messages = []
    let lines = split(source, chr(10))
    let nlines = len(lines)
    # Variable tracking
    let vars = []
    # Control flow tracking
    let prev_is_return = false
    let prev_indent = -1
    for i in range(nlines):
        let lineno = i + 1
        let line = lines[i]
        let ll = line_length(line)
        # Skip blank lines
        if is_blank_line(line):
            prev_is_return = false
            continue
        let ind = measure_indent(line)
        let indent = ind["width"]
        let trimmed = trim_line(line)
        let tlen = len(trimmed)
        if tlen == 0:
            prev_is_return = false
            continue
        # E001: Indentation not multiple of 4
        if indent > 0 and indent % 4 != 0:
            push(messages, make_msg(lineno, 1, SEV_ERROR, "E001", "Indentation is " + str(indent) + " spaces (should be a multiple of 4)"))
        # E002: Mixed tabs and spaces
        if ind["has_tab"] and ind["has_space"]:
            push(messages, make_msg(lineno, 1, SEV_ERROR, "E002", "Mixed tabs and spaces in indentation"))
        # E003: Line too long
        if ll > 120:
            push(messages, make_msg(lineno, 121, SEV_ERROR, "E003", "Line is " + str(ll) + " characters long (maximum 120)"))
        # W003: Unreachable code
        if prev_is_return and indent == prev_indent and indent >= 0:
            push(messages, make_msg(lineno, indent + 1, SEV_WARNING, "W003", "Unreachable code after return/break/continue"))
        # Track return/break/continue
        let is_flow = false
        if startswith(trimmed, "return") and (tlen == 6 or trimmed[6] == " "):
            is_flow = true
        if startswith(trimmed, "break") and (tlen == 5 or trimmed[5] == " "):
            is_flow = true
        if startswith(trimmed, "continue") and (tlen == 8 or trimmed[8] == " "):
            is_flow = true
        if is_flow:
            prev_is_return = true
            prev_indent = indent
        else:
            prev_is_return = false
        # W001/W002: Variable tracking
        if startswith(trimmed, "let ") or startswith(trimmed, "var "):
            let varname = extract_ident_after(trimmed, 4)
            if varname != nil:
                # W002: Shadow check
                for v in vars:
                    if v["name"] == varname:
                        push(messages, make_msg(lineno, 5, SEV_WARNING, "W002", "Variable " + chr(39) + varname + chr(39) + " shadows declaration on line " + str(v["line"])))
                        break
                let entry = {}
                entry["name"] = varname
                entry["line"] = lineno
                entry["indent"] = indent
                push(vars, entry)
        # W004: Empty block
        let buf_end = tlen - 1
        while buf_end >= 0 and (trimmed[buf_end] == " " or trimmed[buf_end] == chr(9)):
            buf_end = buf_end - 1
        if buf_end >= 0 and trimmed[buf_end] == ":":
            let next_idx = i + 1
            while next_idx < nlines and is_blank_line(lines[next_idx]):
                next_idx = next_idx + 1
            if next_idx < nlines:
                let next_ind = measure_indent(lines[next_idx])
                if next_ind["width"] <= indent:
                    push(messages, make_msg(lineno, tlen, SEV_WARNING, "W004", "Empty block (no indented content after " + chr(39) + ":" + chr(39) + ")"))
            else:
                push(messages, make_msg(lineno, tlen, SEV_WARNING, "W004", "Empty block (no indented content after " + chr(39) + ":" + chr(39) + ")"))
        # W005: Bare catch
        if startswith(trimmed, "catch"):
            if tlen == 5 or trimmed[5] == ":":
                let after_idx = 5
                while after_idx < tlen and (trimmed[after_idx] == " " or trimmed[after_idx] == chr(9)):
                    after_idx = after_idx + 1
                if after_idx >= tlen or trimmed[after_idx] == ":":
                    push(messages, make_msg(lineno, 1, SEV_WARNING, "W005", "Bare " + chr(39) + "catch" + chr(39) + " without exception variable (use " + chr(39) + "catch e:" + chr(39) + ")"))
        # S001: Proc name not snake_case
        if startswith(trimmed, "proc ") or startswith(trimmed, "async proc "):
            let offset = 5
            if startswith(trimmed, "async "):
                offset = 11
            let name = extract_ident_after(trimmed, offset)
            if name != nil and name != "init":
                if not is_snake_case(name):
                    push(messages, make_msg(lineno, offset + 1, SEV_STYLE, "S001", "Proc name " + chr(39) + name + chr(39) + " should be snake_case"))
        # S002: Class name not PascalCase
        if startswith(trimmed, "class "):
            let cname = extract_ident_after(trimmed, 6)
            if cname != nil:
                if not is_pascal_case(cname):
                    push(messages, make_msg(lineno, 7, SEV_STYLE, "S002", "Class name " + chr(39) + cname + chr(39) + " should be PascalCase (start with uppercase)"))
        # S003: Missing docstring for top-level proc
        if indent == 0:
            if startswith(trimmed, "proc ") or startswith(trimmed, "async proc "):
                let has_doc = false
                if i > 0:
                    let prev_trimmed = trim_line(lines[i - 1])
                    if len(prev_trimmed) > 0 and prev_trimmed[0] == "#":
                        has_doc = true
                if not has_doc:
                    push(messages, make_msg(lineno, 1, SEV_STYLE, "S003", "Missing docstring (comment) for top-level proc"))
        # S004: Trailing semicolons
        let end2 = ll - 1
        while end2 >= 0:
            let ech = line[end2]
            if ech != " " and ech != chr(9) and ech != chr(13):
                break
            end2 = end2 - 1
        if end2 >= 0 and line[end2] == ";":
            push(messages, make_msg(lineno, end2 + 1, SEV_STYLE, "S004", "Trailing semicolon (not used in Sage)"))
    # W001: Unused variable post-pass
    for v in vars:
        let found = false
        for j in range(v["line"], nlines):
            if name_in_line(lines[j], v["name"]):
                found = true
                break
        if not found:
            push(messages, make_msg(v["line"], 1, SEV_WARNING, "W001", "Variable " + chr(39) + v["name"] + chr(39) + " is declared but never used"))
    return messages

# Format a lint message for display
proc format_message(path, msg):
    return path + ":" + str(msg["line"]) + ":" + str(msg["col"]) + ": " + msg["severity"] + ": [" + msg["rule"] + "] " + msg["message"]

# Lint a file and print results
proc lint_file(path):
    let source = io.read(path)
    if source == nil:
        print "sage lint: cannot open " + chr(39) + path + chr(39)
        return -1
    let messages = lint_source(source)
    for msg in messages:
        print format_message(path, msg)
    return len(messages)
