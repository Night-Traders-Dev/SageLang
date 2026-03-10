# SageLang LSP Server (self-hosted port)
#
# A Language Server Protocol implementation for Sage, ported from src/c/lsp.c.
# Communicates over stdin/stdout using LSP JSON-RPC wire protocol.
#
# Supported features:
#   - textDocument/didOpen, didChange, didClose
#   - textDocument/publishDiagnostics (placeholder)
#   - textDocument/completion (keywords + builtins)
#   - textDocument/hover (keyword/builtin docs)
#   - initialize / initialized / shutdown / exit
#
# Wire protocol adapted for line-based I/O: reads Content-Length header,
# then reads the JSON body line by line until we have enough characters.

# ========================================================================
# Character constants (no escape sequences in Sage)
# ========================================================================
let NL = chr(10)
let TAB = chr(9)
let CR = chr(13)
let DQ = chr(34)
let BS = chr(92)

# ========================================================================
# Document storage
# ========================================================================

# Document: dict with "uri" and "content" keys
proc make_document(uri, content):
    let doc = {}
    doc["uri"] = uri
    doc["content"] = content
    return doc

class DocumentStore:
    proc init():
        self.documents = []

    proc find(uri):
        let i = 0
        while i < len(self.documents):
            let doc = self.documents[i]
            if doc["uri"] == uri:
                return doc
            i = i + 1
        return nil

    proc open_doc(uri, content):
        let existing = self.find(uri)
        if existing != nil:
            existing["content"] = content
            return existing
        let doc = {}
        doc["uri"] = uri
        doc["content"] = content
        push(self.documents, doc)
        return doc

    proc update(uri, content):
        let doc = self.find(uri)
        if doc != nil:
            doc["content"] = content

    proc close_doc(uri):
        let new_docs = []
        let i = 0
        while i < len(self.documents):
            if self.documents[i]["uri"] != uri:
                push(new_docs, self.documents[i])
            i = i + 1
        self.documents = new_docs

# ========================================================================
# JSON helpers (string-based, no external dependency)
# ========================================================================

# Escape a raw string for use inside a JSON string value
proc json_escape(raw):
    if raw == nil:
        return ""
    let out = ""
    let esc_dq = chr(34)
    let esc_bs = chr(92)
    let esc_nl = chr(10)
    let esc_cr = chr(13)
    let esc_tab = chr(9)
    let i = 0
    while i < len(raw):
        let ch = raw[i]
        if ch == esc_dq:
            out = out + esc_bs + esc_dq
            i = i + 1
            continue
        if ch == esc_bs:
            out = out + esc_bs + esc_bs
            i = i + 1
            continue
        if ch == esc_nl:
            out = out + esc_bs + "n"
            i = i + 1
            continue
        if ch == esc_cr:
            out = out + esc_bs + "r"
            i = i + 1
            continue
        if ch == esc_tab:
            out = out + esc_bs + "t"
            i = i + 1
            continue
        out = out + ch
        i = i + 1
    return out

# Extract the string value for a given key from a JSON blob
# Returns the string value or nil if not found
proc json_get_string(json, key):
    if json == nil:
        return nil
    if key == nil:
        return nil
    let dq = chr(34)
    let bs = chr(92)
    let pattern = dq + key + dq
    let idx = indexof(json, pattern)
    if idx < 0:
        return nil
    # Advance past "key"
    var p = idx + len(pattern)
    # Skip whitespace and colon
    var scanning = true
    while scanning:
        if p >= len(json):
            return nil
        let c = json[p]
        if c == " " or c == chr(9) or c == chr(10) or c == chr(13) or c == ":":
            p = p + 1
        if c != " " and c != chr(9) and c != chr(10) and c != chr(13) and c != ":":
            scanning = false
    if json[p] != dq:
        return nil
    p = p + 1
    # Collect characters, handling escapes
    var result = ""
    var reading = true
    while reading:
        if p >= len(json):
            reading = false
            continue
        let c = json[p]
        if c == dq:
            reading = false
            continue
        if c == bs:
            if p + 1 < len(json):
                let next = json[p + 1]
                if next == dq:
                    result = result + dq
                if next == bs:
                    result = result + bs
                if next == "n":
                    result = result + chr(10)
                if next == "t":
                    result = result + chr(9)
                if next == "r":
                    result = result + chr(13)
                if next == "/":
                    result = result + "/"
                if next != dq and next != bs and next != "n" and next != "t" and next != "r" and next != "/":
                    result = result + next
                p = p + 2
            if p + 1 >= len(json):
                p = p + 1
        if c != dq and c != bs:
            result = result + c
            p = p + 1
    return result

# Extract an integer value for a given key, or return default_val
proc json_get_int(json, key, default_val):
    if json == nil:
        return default_val
    if key == nil:
        return default_val
    let dq = chr(34)
    let pattern = dq + key + dq
    let idx = indexof(json, pattern)
    if idx < 0:
        return default_val
    var p = idx + len(pattern)
    # Skip whitespace and colon
    var scanning = true
    while scanning:
        if p >= len(json):
            return default_val
        let c = json[p]
        if c == " " or c == chr(9) or c == chr(10) or c == chr(13) or c == ":":
            p = p + 1
        if c != " " and c != chr(9) and c != chr(10) and c != chr(13) and c != ":":
            scanning = false
    # Read the number
    var num_str = ""
    var reading = true
    while reading:
        if p >= len(json):
            reading = false
            continue
        let c = json[p]
        if c == "-" or (ord(c) >= 48 and ord(c) <= 57):
            num_str = num_str + c
            p = p + 1
        if c != "-" and not (ord(c) >= 48 and ord(c) <= 57):
            reading = false
    if len(num_str) < 1:
        return default_val
    return tonumber(num_str)

# Extract a nested object {...} for a given key
# Returns the substring including braces, or nil
proc json_get_object(json, key):
    if json == nil:
        return nil
    if key == nil:
        return nil
    let dq = chr(34)
    let pattern = dq + key + dq
    let idx = indexof(json, pattern)
    if idx < 0:
        return nil
    var p = idx + len(pattern)
    # Skip whitespace and colon
    var scanning = true
    while scanning:
        if p >= len(json):
            return nil
        let c = json[p]
        if c == " " or c == chr(9) or c == chr(10) or c == chr(13) or c == ":":
            p = p + 1
        if c != " " and c != chr(9) and c != chr(10) and c != chr(13) and c != ":":
            scanning = false
    if json[p] != "{":
        return nil
    var depth = 0
    let start = p
    var in_string = false
    var collecting = true
    while collecting:
        if p >= len(json):
            return nil
        let c = json[p]
        if c == chr(92) and in_string:
            p = p + 2
            continue
        if c == dq:
            in_string = not in_string
        if not in_string:
            if c == "{":
                depth = depth + 1
            if c == "}":
                depth = depth - 1
                if depth < 1:
                    return slice(json, start, p + 1)
        p = p + 1
    return nil

# ========================================================================
# Completion data
# ========================================================================

proc make_completion(label, kind, detail):
    let item = {}
    item["label"] = label
    item["kind"] = kind
    item["detail"] = detail
    return item

# CompletionItemKind: 14=Keyword, 3=Function
proc get_completions():
    let items = []
    # Keywords
    push(items, make_completion("let", 14, "Variable declaration"))
    push(items, make_completion("var", 14, "Mutable variable declaration"))
    push(items, make_completion("proc", 14, "Function/procedure definition"))
    push(items, make_completion("if", 14, "Conditional statement"))
    push(items, make_completion("else", 14, "Else branch"))
    push(items, make_completion("while", 14, "While loop"))
    push(items, make_completion("for", 14, "For loop"))
    push(items, make_completion("in", 14, "In operator / for-in"))
    push(items, make_completion("return", 14, "Return from function"))
    push(items, make_completion("print", 14, "Print statement"))
    push(items, make_completion("and", 14, "Logical AND"))
    push(items, make_completion("or", 14, "Logical OR"))
    push(items, make_completion("not", 14, "Logical NOT"))
    push(items, make_completion("true", 14, "Boolean true"))
    push(items, make_completion("false", 14, "Boolean false"))
    push(items, make_completion("nil", 14, "Nil value"))
    push(items, make_completion("class", 14, "Class definition"))
    push(items, make_completion("self", 14, "Self reference"))
    push(items, make_completion("init", 14, "Constructor"))
    push(items, make_completion("import", 14, "Module import"))
    push(items, make_completion("from", 14, "Import from"))
    push(items, make_completion("as", 14, "Import alias"))
    push(items, make_completion("match", 14, "Pattern matching"))
    push(items, make_completion("case", 14, "Match case"))
    push(items, make_completion("try", 14, "Try block"))
    push(items, make_completion("catch", 14, "Catch handler"))
    push(items, make_completion("finally", 14, "Finally block"))
    push(items, make_completion("raise", 14, "Raise exception"))
    push(items, make_completion("break", 14, "Break loop"))
    push(items, make_completion("continue", 14, "Continue loop"))
    push(items, make_completion("defer", 14, "Deferred execution"))
    push(items, make_completion("yield", 14, "Yield from generator"))
    push(items, make_completion("async", 14, "Async function"))
    push(items, make_completion("await", 14, "Await expression"))
    # Builtin functions
    push(items, make_completion("str", 3, "Convert value to string"))
    push(items, make_completion("len", 3, "Get length of string/array/dict"))
    push(items, make_completion("tonumber", 3, "Convert string to number"))
    push(items, make_completion("clock", 3, "Get current time in seconds"))
    push(items, make_completion("input", 3, "Read a line from stdin"))
    push(items, make_completion("asm_arch", 3, "Get host architecture string"))
    push(items, make_completion("push", 3, "Append element to array"))
    push(items, make_completion("pop", 3, "Remove and return last element"))
    push(items, make_completion("range", 3, "Generate array of numbers"))
    push(items, make_completion("slice", 3, "Slice array or string"))
    push(items, make_completion("split", 3, "Split string by delimiter"))
    push(items, make_completion("join", 3, "Join array into string"))
    push(items, make_completion("replace", 3, "Replace substring"))
    push(items, make_completion("upper", 3, "Convert string to uppercase"))
    push(items, make_completion("lower", 3, "Convert string to lowercase"))
    push(items, make_completion("strip", 3, "Strip whitespace from string"))
    push(items, make_completion("dict_keys", 3, "Get dictionary keys as array"))
    push(items, make_completion("dict_values", 3, "Get dictionary values as array"))
    push(items, make_completion("dict_has", 3, "Check if dictionary has key"))
    push(items, make_completion("dict_delete", 3, "Delete key from dictionary"))
    push(items, make_completion("mem_alloc", 3, "Allocate raw memory"))
    push(items, make_completion("mem_free", 3, "Free raw memory"))
    push(items, make_completion("mem_read", 3, "Read byte from memory"))
    push(items, make_completion("mem_write", 3, "Write byte to memory"))
    push(items, make_completion("mem_size", 3, "Get memory block size"))
    push(items, make_completion("struct_def", 3, "Define a struct type"))
    push(items, make_completion("struct_new", 3, "Create struct instance"))
    push(items, make_completion("struct_get", 3, "Get struct field"))
    push(items, make_completion("struct_set", 3, "Set struct field"))
    push(items, make_completion("struct_size", 3, "Get struct size in bytes"))
    return items

# ========================================================================
# Hover documentation
# ========================================================================

proc build_hover_docs():
    let docs = {}
    let nl = chr(10)
    let bt = "`"
    let bt3 = "```"
    # Keywords
    docs["let"] = "**let** - Declare an immutable variable." + nl + nl + bt3 + "sage" + nl + "let x = 42" + nl + bt3
    docs["var"] = "**var** - Declare a mutable variable." + nl + nl + bt3 + "sage" + nl + "var counter = 0" + nl + "counter = counter + 1" + nl + bt3
    docs["proc"] = "**proc** - Define a function/procedure." + nl + nl + bt3 + "sage" + nl + "proc greet(name):" + nl + "    print " + DQ + "Hello, " + DQ + " + name" + nl + bt3
    docs["if"] = "**if** - Conditional statement." + nl + nl + bt3 + "sage" + nl + "if x > 0:" + nl + "    print " + DQ + "positive" + DQ + nl + "else:" + nl + "    print " + DQ + "non-positive" + DQ + nl + bt3
    docs["while"] = "**while** - Loop while condition is true." + nl + nl + bt3 + "sage" + nl + "while x > 0:" + nl + "    x = x - 1" + nl + bt3
    docs["for"] = "**for** - Iterate over a range or collection." + nl + nl + bt3 + "sage" + nl + "for i in range(10):" + nl + "    print i" + nl + bt3
    docs["class"] = "**class** - Define a class." + nl + nl + bt3 + "sage" + nl + "class Point:" + nl + "    init(self, x, y):" + nl + "        self.x = x" + nl + "        self.y = y" + nl + bt3
    docs["import"] = "**import** - Import a module." + nl + nl + bt3 + "sage" + nl + "import math" + nl + bt3
    docs["match"] = "**match** - Pattern matching." + nl + nl + bt3 + "sage" + nl + "match value:" + nl + "    case 1:" + nl + "        print " + DQ + "one" + DQ + nl + "    case 2:" + nl + "        print " + DQ + "two" + DQ + nl + "    default:" + nl + "        print " + DQ + "other" + DQ + nl + bt3
    docs["try"] = "**try** - Exception handling." + nl + nl + bt3 + "sage" + nl + "try:" + nl + "    risky_operation()" + nl + "catch e:" + nl + "    print " + DQ + "Error: " + DQ + " + str(e)" + nl + bt3
    docs["print"] = "**print** - Print a value to stdout." + nl + nl + bt3 + "sage" + nl + "print " + DQ + "Hello, world!" + DQ + nl + "print 42" + nl + bt3
    docs["return"] = "**return** - Return a value from a function." + nl + nl + bt3 + "sage" + nl + "proc add(a, b):" + nl + "    return a + b" + nl + bt3
    # Builtin functions
    docs["str"] = "**str(value)** - Convert any value to its string representation."
    docs["len"] = "**len(value)** - Get the length of a string, array, or dictionary."
    docs["tonumber"] = "**tonumber(s)** - Convert a string to a number."
    docs["clock"] = "**clock()** - Returns current time in seconds (float)."
    docs["input"] = "**input(prompt)** - Read a line from stdin with optional prompt."
    docs["push"] = "**push(array, value)** - Append an element to an array."
    docs["pop"] = "**pop(array)** - Remove and return the last element of an array."
    docs["range"] = "**range(n)** or **range(start, end)** or **range(start, end, step)** - Generate an array of numbers."
    docs["slice"] = "**slice(value, start, end)** - Slice an array or string."
    docs["split"] = "**split(string, delimiter)** - Split a string by delimiter."
    docs["join"] = "**join(array, separator)** - Join array elements into a string."
    docs["replace"] = "**replace(string, old, new)** - Replace all occurrences of a substring."
    docs["upper"] = "**upper(string)** - Convert string to uppercase."
    docs["lower"] = "**lower(string)** - Convert string to lowercase."
    docs["strip"] = "**strip(string)** - Remove leading/trailing whitespace."
    docs["dict_keys"] = "**dict_keys(dict)** - Get all keys of a dictionary as an array."
    docs["dict_values"] = "**dict_values(dict)** - Get all values of a dictionary as an array."
    docs["dict_has"] = "**dict_has(dict, key)** - Check if dictionary contains a key."
    docs["dict_delete"] = "**dict_delete(dict, key)** - Delete a key from a dictionary."
    docs["mem_alloc"] = "**mem_alloc(size)** - Allocate a raw memory block of given size."
    docs["mem_free"] = "**mem_free(ptr)** - Free a previously allocated memory block."
    docs["mem_read"] = "**mem_read(ptr, offset)** - Read a byte from memory at offset."
    docs["mem_write"] = "**mem_write(ptr, offset, value)** - Write a byte to memory at offset."
    docs["mem_size"] = "**mem_size(ptr)** - Get the size of a memory block."
    docs["struct_def"] = "**struct_def(name, fields)** - Define a struct type with named fields."
    docs["struct_new"] = "**struct_new(type, ...)** - Create a new struct instance."
    docs["struct_get"] = "**struct_get(instance, field)** - Get a field from a struct."
    docs["struct_set"] = "**struct_set(instance, field, value)** - Set a field on a struct."
    docs["struct_size"] = "**struct_size(type)** - Get the size of a struct type in bytes."
    docs["asm_arch"] = "**asm_arch()** - Returns the host architecture as a string."
    return docs

proc get_hover_doc(word, hover_docs):
    if dict_has(hover_docs, word):
        return hover_docs[word]
    return nil

# ========================================================================
# Word extraction
# ========================================================================

proc is_word_char(ch):
    let c = ord(ch)
    if c == 95:
        return true
    if c >= 97 and c <= 122:
        return true
    if c >= 65 and c <= 90:
        return true
    if c >= 48 and c <= 57:
        return true
    return false

proc get_word_at(content, line, character):
    if content == nil:
        return nil
    # Find the start of the target line
    let lines = split(content, chr(10))
    if line >= len(lines):
        return nil
    let target_line = lines[line]
    if character >= len(target_line):
        return nil
    # Find word boundaries
    var start = character
    var end_pos = character
    while start > 0:
        if not is_word_char(target_line[start - 1]):
            break
        start = start - 1
    while end_pos < len(target_line):
        if not is_word_char(target_line[end_pos]):
            break
        end_pos = end_pos + 1
    if start == end_pos:
        return nil
    return slice(target_line, start, end_pos)

# ========================================================================
# Diagnostics (placeholder -- will integrate with linter.sage later)
# ========================================================================

proc generate_diagnostics(content, filename):
    # Returns array of diagnostic dicts
    # For now, return empty array (linter integration can come later)
    return []

# ========================================================================
# LSP message building
# ========================================================================

proc make_response(id_str, result_json):
    let dq = chr(34)
    # Try to determine if id_str is numeric
    var is_numeric = true
    if len(id_str) < 1:
        is_numeric = false
    for i in range(len(id_str)):
        let c = ord(id_str[i])
        if c != 45 and not (c >= 48 and c <= 57):
            is_numeric = false
    if is_numeric:
        return "{" + dq + "jsonrpc" + dq + ":" + dq + "2.0" + dq + "," + dq + "id" + dq + ":" + id_str + "," + dq + "result" + dq + ":" + result_json + "}"
    return "{" + dq + "jsonrpc" + dq + ":" + dq + "2.0" + dq + "," + dq + "id" + dq + ":" + dq + id_str + dq + "," + dq + "result" + dq + ":" + result_json + "}"

proc make_notification(method, params_json):
    let dq = chr(34)
    return "{" + dq + "jsonrpc" + dq + ":" + dq + "2.0" + dq + "," + dq + "method" + dq + ":" + dq + method + dq + "," + dq + "params" + dq + ":" + params_json + "}"

proc make_error_response(id_str, code, message):
    let dq = chr(34)
    let esc_msg = json_escape(message)
    var is_numeric = true
    if len(id_str) < 1:
        is_numeric = false
    for i in range(len(id_str)):
        let c = ord(id_str[i])
        if c != 45 and not (c >= 48 and c <= 57):
            is_numeric = false
    var id_part = dq + id_str + dq
    if is_numeric:
        id_part = id_str
    return "{" + dq + "jsonrpc" + dq + ":" + dq + "2.0" + dq + "," + dq + "id" + dq + ":" + id_part + "," + dq + "error" + dq + ":{" + dq + "code" + dq + ":" + str(code) + "," + dq + "message" + dq + ":" + dq + esc_msg + dq + "}}"

# ========================================================================
# LSP capabilities (initialize result)
# ========================================================================

proc get_initialize_result():
    let dq = chr(34)
    let result = "{"
    result = result + dq + "capabilities" + dq + ":{"
    result = result + dq + "textDocumentSync" + dq + ":{"
    result = result + dq + "openClose" + dq + ":true,"
    result = result + dq + "change" + dq + ":1"
    result = result + "},"
    result = result + dq + "completionProvider" + dq + ":{"
    result = result + dq + "triggerCharacters" + dq + ":[" + dq + "." + dq + "]"
    result = result + "},"
    result = result + dq + "hoverProvider" + dq + ":true"
    result = result + "},"
    result = result + dq + "serverInfo" + dq + ":{"
    result = result + dq + "name" + dq + ":" + dq + "sage-lsp" + dq + ","
    result = result + dq + "version" + dq + ":" + dq + "0.1.0" + dq
    result = result + "}"
    result = result + "}"
    return result

# ========================================================================
# Completion response builder
# ========================================================================

proc build_completion_response(id_str):
    let dq = chr(34)
    let items = get_completions()
    var items_json = "["
    for i in range(len(items)):
        let item = items[i]
        let esc_label = json_escape(item["label"])
        let esc_detail = json_escape(item["detail"])
        if i > 0:
            items_json = items_json + ","
        items_json = items_json + "{"
        items_json = items_json + dq + "label" + dq + ":" + dq + esc_label + dq + ","
        items_json = items_json + dq + "kind" + dq + ":" + str(item["kind"]) + ","
        items_json = items_json + dq + "detail" + dq + ":" + dq + esc_detail + dq
        items_json = items_json + "}"
    items_json = items_json + "]"
    return make_response(id_str, items_json)

# ========================================================================
# Hover response builder
# ========================================================================

proc build_hover_response(id_str, doc_content, line, character, hover_docs):
    let dq = chr(34)
    let word = get_word_at(doc_content, line, character)
    if word == nil:
        return make_response(id_str, "null")
    let hover_text = get_hover_doc(word, hover_docs)
    if hover_text == nil:
        return make_response(id_str, "null")
    let esc_doc = json_escape(hover_text)
    var result_json = "{"
    result_json = result_json + dq + "contents" + dq + ":{"
    result_json = result_json + dq + "kind" + dq + ":" + dq + "markdown" + dq + ","
    result_json = result_json + dq + "value" + dq + ":" + dq + esc_doc + dq
    result_json = result_json + "}}"
    return make_response(id_str, result_json)

# ========================================================================
# Diagnostics response builder
# ========================================================================

proc build_diagnostics_notification(uri, content):
    let dq = chr(34)
    let diags = generate_diagnostics(content, "buffer")
    var diags_json = "["
    for i in range(len(diags)):
        let d = diags[i]
        if i > 0:
            diags_json = diags_json + ","
        let line_num = d["line"]
        if line_num > 0:
            line_num = line_num - 1
        let col_num = d["col"]
        if col_num > 0:
            col_num = col_num - 1
        let sev = 3
        if d["severity"] == "error":
            sev = 1
        if d["severity"] == "warning":
            sev = 2
        if d["severity"] == "style":
            sev = 4
        let esc_msg = json_escape(d["message"])
        let esc_src = json_escape(d["source"])
        diags_json = diags_json + "{"
        diags_json = diags_json + dq + "range" + dq + ":{"
        diags_json = diags_json + dq + "start" + dq + ":{" + dq + "line" + dq + ":" + str(line_num) + "," + dq + "character" + dq + ":" + str(col_num) + "},"
        diags_json = diags_json + dq + "end" + dq + ":{" + dq + "line" + dq + ":" + str(line_num) + "," + dq + "character" + dq + ":" + str(col_num + 1) + "}"
        diags_json = diags_json + "},"
        diags_json = diags_json + dq + "severity" + dq + ":" + str(sev) + ","
        diags_json = diags_json + dq + "source" + dq + ":" + dq + "sage-lint" + dq + ","
        diags_json = diags_json + dq + "message" + dq + ":" + dq + esc_msg + dq
        diags_json = diags_json + "}"
    diags_json = diags_json + "]"
    let esc_uri = json_escape(uri)
    var params_json = "{"
    params_json = params_json + dq + "uri" + dq + ":" + dq + esc_uri + dq + ","
    params_json = params_json + dq + "diagnostics" + dq + ":" + diags_json
    params_json = params_json + "}"
    return make_notification("textDocument/publishDiagnostics", params_json)

proc build_clear_diagnostics_notification(uri):
    let dq = chr(34)
    let esc_uri = json_escape(uri)
    var params_json = "{"
    params_json = params_json + dq + "uri" + dq + ":" + dq + esc_uri + dq + ","
    params_json = params_json + dq + "diagnostics" + dq + ":[]"
    params_json = params_json + "}"
    return make_notification("textDocument/publishDiagnostics", params_json)

# ========================================================================
# ID extraction from JSON
# ========================================================================

proc extract_id(json):
    let dq = chr(34)
    let pattern = dq + "id" + dq
    let idx = indexof(json, pattern)
    if idx < 0:
        return ""
    var p = idx + len(pattern)
    # Skip whitespace and colon
    var scanning = true
    while scanning:
        if p >= len(json):
            return ""
        let c = json[p]
        if c == " " or c == chr(9) or c == chr(10) or c == chr(13) or c == ":":
            p = p + 1
        if c != " " and c != chr(9) and c != chr(10) and c != chr(13) and c != ":":
            scanning = false
    # Read the id value (string or number)
    if json[p] == dq:
        p = p + 1
        var id_str = ""
        while p < len(json):
            if json[p] == dq:
                return id_str
            id_str = id_str + json[p]
            p = p + 1
        return id_str
    # Numeric id
    var id_str = ""
    while p < len(json):
        let c = json[p]
        if c == "-" or (ord(c) >= 48 and ord(c) <= 57):
            id_str = id_str + c
            p = p + 1
        if c != "-" and not (ord(c) >= 48 and ord(c) <= 57):
            return id_str
    return id_str

# ========================================================================
# Wire protocol: send LSP message with Content-Length header
# ========================================================================

proc lsp_send(json_msg):
    let header = "Content-Length: " + str(len(json_msg))
    print header
    print ""
    # Print the JSON body without trailing newline is not possible
    # with print (it always adds newline). We use print and the
    # client must handle the extra newline.
    print json_msg

# ========================================================================
# Wire protocol: read LSP message from stdin
# Returns the JSON body string or nil on EOF
# ========================================================================

proc lsp_read_message():
    # Read headers until empty line
    var content_length = -1
    var reading_headers = true
    while reading_headers:
        let line = input("")
        if line == nil:
            return nil
        # Strip trailing CR if present
        var clean = line
        if len(clean) > 0:
            if clean[len(clean) - 1] == chr(13):
                clean = slice(clean, 0, len(clean) - 1)
        # Empty line terminates headers
        if len(clean) < 1:
            reading_headers = false
            continue
        # Check for Content-Length
        if startswith(clean, "Content-Length:"):
            let val = strip(slice(clean, 15, len(clean)))
            content_length = tonumber(val)
    if content_length < 1:
        return nil
    # Read the JSON body
    # Since Sage only has line-based input(), we read lines and
    # accumulate until we have enough characters
    var body = ""
    while len(body) < content_length:
        let line = input("")
        if line == nil:
            return nil
        if len(body) > 0:
            body = body + chr(10) + line
        if len(body) < 1:
            body = line
    return body

# ========================================================================
# Main LSP server loop
# ========================================================================

proc lsp_run():
    let store = DocumentStore()
    let hover_docs = build_hover_docs()
    var shutdown_requested = false
    var running = true

    while running:
        let body = lsp_read_message()
        if body == nil:
            running = false
            continue

        let method = json_get_string(body, "method")
        if method == nil:
            # Response or unknown message, skip
            continue

        let id_str = extract_id(body)

        # ---- Lifecycle ----
        if method == "initialize":
            let result = get_initialize_result()
            lsp_send(make_response(id_str, result))
            continue

        if method == "initialized":
            # No-op notification
            continue

        if method == "shutdown":
            shutdown_requested = true
            lsp_send(make_response(id_str, "null"))
            continue

        if method == "exit":
            running = false
            continue

        # ---- Document sync ----
        if method == "textDocument/didOpen":
            let params = json_get_object(body, "params")
            if params != nil:
                let td = json_get_object(params, "textDocument")
                if td != nil:
                    let uri = json_get_string(td, "uri")
                    let text = json_get_string(td, "text")
                    if uri != nil and text != nil:
                        store.open_doc(uri, text)
                        lsp_send(build_diagnostics_notification(uri, text))
            continue

        if method == "textDocument/didChange":
            let params = json_get_object(body, "params")
            if params != nil:
                let td = json_get_object(params, "textDocument")
                let uri = nil
                if td != nil:
                    uri = json_get_string(td, "uri")
                # Extract text from contentChanges
                let text = nil
                let cc_idx = indexof(params, "contentChanges")
                if cc_idx >= 0:
                    text = json_get_string(params, "text")
                if uri != nil and text != nil:
                    store.update(uri, text)
                    lsp_send(build_diagnostics_notification(uri, text))
            continue

        if method == "textDocument/didClose":
            let params = json_get_object(body, "params")
            if params != nil:
                let td = json_get_object(params, "textDocument")
                if td != nil:
                    let uri = json_get_string(td, "uri")
                    if uri != nil:
                        store.close_doc(uri)
                        lsp_send(build_clear_diagnostics_notification(uri))
            continue

        # ---- Features ----
        if method == "textDocument/completion":
            lsp_send(build_completion_response(id_str))
            continue

        if method == "textDocument/hover":
            let params = json_get_object(body, "params")
            var uri = nil
            var line = 0
            var character = 0
            if params != nil:
                let td = json_get_object(params, "textDocument")
                let pos = json_get_object(params, "position")
                if td != nil:
                    uri = json_get_string(td, "uri")
                if pos != nil:
                    line = json_get_int(pos, "line", 0)
                    character = json_get_int(pos, "character", 0)
            if uri != nil:
                let doc = store.find(uri)
                if doc != nil:
                    lsp_send(build_hover_response(id_str, doc["content"], line, character, hover_docs))
                    continue
            lsp_send(make_response(id_str, "null"))
            continue

        # ---- Unknown method ----
        if len(id_str) > 0:
            lsp_send(make_error_response(id_str, -32601, "Method not found: " + method))

# Entry point: call lsp_run() to start the server
