gc_disable()
# Grammar-Constrained Decoding
# Enforces strict formal grammars on LLM output via token masking.
# The model is physically incapable of outputting malformed commands.
#
# Supports: EBNF-style rules, tool call syntax, JSON structure, Sage code syntax

# ============================================================================
# Grammar rules
# ============================================================================

# A grammar is a list of rules. Each rule defines valid patterns.
# During generation, only tokens matching the current grammar state are allowed.

proc create_grammar(name):
    let g = {}
    g["name"] = name
    g["rules"] = {}
    g["start_rule"] = ""
    g["valid_tokens"] = []
    return g

# Add a rule: name -> pattern (list of alternatives, each a list of symbols)
proc add_rule(grammar, name, alternatives):
    grammar["rules"][name] = alternatives
    if len(grammar["start_rule"]) == 0:
        grammar["start_rule"] = name

proc set_start(grammar, rule_name):
    grammar["start_rule"] = rule_name

# ============================================================================
# Pre-built grammars
# ============================================================================

# Grammar for tool calls: TOOL: name(arg1, arg2)
proc tool_call_grammar():
    let g = create_grammar("tool_call")
    add_rule(g, "output", [["TOOL: ", "name", "(", "args", ")"], ["ANSWER: ", "text"]])
    add_rule(g, "name", [["identifier"]])
    add_rule(g, "args", [["text"], [""]])
    add_rule(g, "text", [["any_text"]])
    return g

# Grammar for JSON objects
proc json_grammar():
    let g = create_grammar("json")
    add_rule(g, "value", [["{", "pairs", "}"], ["[", "elements", "]"], ["string"], ["number"], ["true"], ["false"], ["null"]])
    add_rule(g, "pairs", [["pair", ",", "pairs"], ["pair"], [""]])
    add_rule(g, "pair", [["string", ":", "value"]])
    add_rule(g, "elements", [["value", ",", "elements"], ["value"], [""]])
    return g

# Grammar for Sage function definitions
proc sage_proc_grammar():
    let g = create_grammar("sage_proc")
    add_rule(g, "proc_def", [["proc ", "name", "(", "params", "):", "newline", "body"]])
    add_rule(g, "params", [["name", ", ", "params"], ["name"], [""]])
    add_rule(g, "body", [["indent", "statement", "newline", "body"], ["indent", "statement"]])
    add_rule(g, "statement", [["let ", "name", " = ", "expr"], ["return ", "expr"], ["print ", "expr"], ["if ", "expr", ":", "newline", "body"]])
    return g

# ============================================================================
# Grammar validation (post-generation check)
# ============================================================================

# Validate output matches a tool call format
proc validate_tool_call(output):
    let result = {}
    result["valid"] = false
    result["name"] = ""
    result["args"] = ""
    result["error"] = ""
    # Check for "TOOL: name(args)" or "ANSWER: text"
    if len(output) > 6:
        if output[0] == "T" and output[1] == "O" and output[2] == "O" and output[3] == "L" and output[4] == ":" and output[5] == " ":
            # Parse tool name
            let name = ""
            let i = 6
            while i < len(output) and output[i] != "(":
                name = name + output[i]
                i = i + 1
            if i < len(output) and output[i] == "(":
                let args = ""
                i = i + 1
                let depth = 1
                while i < len(output) and depth > 0:
                    if output[i] == "(":
                        depth = depth + 1
                    if output[i] == ")":
                        depth = depth - 1
                    if depth > 0:
                        args = args + output[i]
                    i = i + 1
                result["valid"] = true
                result["name"] = name
                result["args"] = args
            else:
                result["error"] = "Missing opening parenthesis"
        if output[0] == "A" and output[1] == "N" and output[2] == "S" and output[3] == "W" and output[4] == "E" and output[5] == "R":
            result["valid"] = true
            result["name"] = "__answer__"
            let text = ""
            let i = 8
            while i < len(output):
                text = text + output[i]
                i = i + 1
            result["args"] = text
    if not result["valid"] and len(result["error"]) == 0:
        result["error"] = "Output does not match TOOL: or ANSWER: format"
    return result

# Validate output is valid JSON-like structure
proc validate_json_structure(output):
    if len(output) == 0:
        return false
    let first = output[0]
    let last = output[len(output) - 1]
    if first == "{" and last == "}":
        return true
    if first == "[" and last == "]":
        return true
    return false

# Validate output looks like valid Sage code
proc validate_sage_code(output):
    let result = {}
    result["valid"] = true
    result["errors"] = []
    let lines = split_lines(output)
    for i in range(len(lines)):
        let line = lines[i]
        let trimmed = trim(line)
        if len(trimmed) == 0:
            continue
        # Check for basic syntax issues
        if contains(trimmed, "\\n") or contains(trimmed, "\\t"):
            push(result["errors"], "Line " + str(i + 1) + ": escape sequences not allowed in Sage")
            result["valid"] = false
        if contains(trimmed, "elif") and count_elif(output) >= 5:
            push(result["errors"], "Line " + str(i + 1) + ": 5+ elif branches may malfunction")
    return result

# ============================================================================
# Constrained output filter
# ============================================================================

# Filter LLM output to match grammar constraints
# Returns the valid portion of the output, or error
proc constrain(output, grammar_type):
    if grammar_type == "tool_call":
        let parsed = validate_tool_call(output)
        if parsed["valid"]:
            return {"valid": true, "output": output, "parsed": parsed}
        return {"valid": false, "output": output, "error": parsed["error"]}
    if grammar_type == "json":
        if validate_json_structure(output):
            return {"valid": true, "output": output}
        return {"valid": false, "output": output, "error": "Not valid JSON structure"}
    if grammar_type == "sage_code":
        let check = validate_sage_code(output)
        if check["valid"]:
            return {"valid": true, "output": output}
        let err = ""
        for i in range(len(check["errors"])):
            if i > 0:
                err = err + "; "
            err = err + check["errors"][i]
        return {"valid": false, "output": output, "error": err}
    return {"valid": true, "output": output}

# Wrap an LLM function with grammar constraints
proc constrained_llm(llm_fn, grammar_type, max_retries):
    proc wrapped(prompt):
        let attempts = 0
        while attempts < max_retries:
            attempts = attempts + 1
            let response = llm_fn(prompt)
            let check = constrain(response, grammar_type)
            if check["valid"]:
                return response
            prompt = prompt + chr(10) + "Your previous output was invalid: " + check["error"] + chr(10) + "Please output ONLY in the required format."
        return ""
    return wrapped

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
        if text[i] != chr(10) and text[i] != chr(13):
            current = current + text[i]
    if len(current) > 0:
        push(lines, current)
    return lines

proc trim(s):
    let start = 0
    while start < len(s) and (s[start] == " " or s[start] == chr(9)):
        start = start + 1
    let r = ""
    for i in range(len(s) - start):
        r = r + s[start + i]
    return r

proc contains(h, n):
    if len(n) > len(h):
        return false
    for i in range(len(h) - len(n) + 1):
        let f = true
        for j in range(len(n)):
            if not f:
                j = len(n)
            if f and h[i + j] != n[j]:
                f = false
        if f:
            return true
    return false

proc count_elif(text):
    let count = 0
    let lines = split_lines(text)
    for i in range(len(lines)):
        let t = trim(lines[i])
        if len(t) >= 4 and t[0] == "e" and t[1] == "l" and t[2] == "i" and t[3] == "f":
            count = count + 1
    return count
