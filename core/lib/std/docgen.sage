gc_disable()
# Documentation generator
# Extracts doc comments from Sage source files and generates documentation

# ============================================================================
# Source parsing
# ============================================================================

# Extract doc comments (lines starting with # before proc/class/let)
proc extract_docs(source):
    let entries = []
    let lines = split_lines(source)
    let i = 0
    while i < len(lines):
        let line = lines[i]
        let trimmed = trim_line(line)
        # Check if this is a proc or class definition
        let is_proc = starts_with_word(trimmed, "proc")
        let is_class = starts_with_word(trimmed, "class")
        let is_let = starts_with_word(trimmed, "let")
        if is_proc or is_class or is_let:
            # Collect preceding comments
            let doc_lines = []
            let j = i - 1
            while j >= 0 and starts_with_char(trim_line(lines[j]), "#"):
                let comment = trim_line(lines[j])
                # Remove leading # and space
                let text = ""
                let k = 1
                if k < len(comment) and comment[k] == " ":
                    k = 2
                while k < len(comment):
                    text = text + comment[k]
                    k = k + 1
                push(doc_lines, text)
                j = j - 1
            # Reverse doc_lines (we collected bottom-up)
            let doc = []
            let di = len(doc_lines) - 1
            while di >= 0:
                push(doc, doc_lines[di])
                di = di - 1
            let entry = {}
            entry["line"] = i + 1
            entry["signature"] = trimmed
            entry["doc"] = doc
            if is_proc:
                entry["type"] = "proc"
                entry["name"] = extract_name(trimmed, "proc")
            if is_class:
                entry["type"] = "class"
                entry["name"] = extract_name(trimmed, "class")
            if is_let:
                entry["type"] = "let"
                entry["name"] = extract_name(trimmed, "let")
            push(entries, entry)
        i = i + 1
    return entries

# ============================================================================
# Output formatting
# ============================================================================

# Generate markdown documentation
proc to_markdown(entries, module_name):
    let nl = chr(10)
    let output = "# " + module_name + nl + nl
    # Group by type
    let procs = []
    let classes = []
    let constants = []
    for i in range(len(entries)):
        if entries[i]["type"] == "proc":
            push(procs, entries[i])
        if entries[i]["type"] == "class":
            push(classes, entries[i])
        if entries[i]["type"] == "let":
            push(constants, entries[i])
    if len(constants) > 0:
        output = output + "## Constants" + nl + nl
        for i in range(len(constants)):
            output = output + "### `" + constants[i]["signature"] + "`" + nl
            let doc = constants[i]["doc"]
            for j in range(len(doc)):
                output = output + doc[j] + nl
            output = output + nl
    if len(classes) > 0:
        output = output + "## Classes" + nl + nl
        for i in range(len(classes)):
            output = output + "### `" + classes[i]["name"] + "`" + nl
            let doc = classes[i]["doc"]
            for j in range(len(doc)):
                output = output + doc[j] + nl
            output = output + nl
    if len(procs) > 0:
        output = output + "## Functions" + nl + nl
        for i in range(len(procs)):
            output = output + "### `" + procs[i]["signature"] + "`" + nl
            let doc = procs[i]["doc"]
            for j in range(len(doc)):
                output = output + doc[j] + nl
            output = output + nl
    return output

# ============================================================================
# Helpers
# ============================================================================

proc split_lines(text):
    let lines = []
    let current = ""
    for i in range(len(text)):
        if text[i] == chr(10):
            push(lines, current)
            current = ""
        else:
            if text[i] != chr(13):
                current = current + text[i]
    if len(current) > 0:
        push(lines, current)
    return lines

proc trim_line(line):
    let start = 0
    while start < len(line) and (line[start] == " " or line[start] == chr(9)):
        start = start + 1
    let result = ""
    for i in range(len(line) - start):
        result = result + line[start + i]
    return result

proc starts_with_char(s, ch):
    if len(s) == 0:
        return false
    return s[0] == ch

proc starts_with_word(s, word):
    if len(s) < len(word):
        return false
    for i in range(len(word)):
        if s[i] != word[i]:
            return false
    if len(s) > len(word):
        let next = s[len(word)]
        return next == " " or next == "("
    return true

proc extract_name(signature, keyword):
    let start = len(keyword) + 1
    let name = ""
    while start < len(signature):
        let c = signature[start]
        if c == "(" or c == ":" or c == " ":
            return name
        name = name + c
        start = start + 1
    return name
