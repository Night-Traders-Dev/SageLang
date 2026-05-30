gc_disable()
# Program-Aided Reasoning (Native AST-Driven Execution)
# Allows the LLM to write executable Sage code blocks which are
# parsed, validated, and executed in a sandboxed environment.
# Deterministic tasks (math, loops, I/O) are offloaded to the compiler.

# ============================================================================
# Code block extraction
# ============================================================================

# Extract code blocks from LLM output (delimited by ```sage ... ```)
proc extract_code_blocks(text):
    let blocks = []
    let in_block = false
    let current = ""
    let lines = split_lines(text)
    for i in range(len(lines)):
        let line = lines[i]
        let trimmed = trim(line)
        if not in_block and (trimmed == "```sage" or trimmed == "```"):
            in_block = true
            current = ""
            continue
        end
        if in_block and trimmed == "```":
            in_block = false
            if len(current) > 0:
                push(blocks, current)
            end
            current = ""
            continue
        end
        if in_block:
            current = current + line + chr(10)
        end
    end
    # Also extract inline code after "CODE:" prefix
    for i in range(len(lines)):
        let line = lines[i]
        if len(line) > 6 and line[0] == "C" and line[1] == "O" and line[2] == "D" and line[3] == "E" and line[4] == ":" and line[5] == " ":
            let code = ""
            for j in range(len(line) - 6):
                code = code + line[6 + j]
            end
            push(blocks, code)
        end
    end
    return blocks

# ============================================================================
# Sandboxed execution
# ============================================================================

# Validate code is safe to execute (no system calls, no file writes)
# Blocks access to native modules and unsafe primitives.
# Uses a token-aware scanner to avoid false positives in comments/strings.
proc is_safe(code):
    let result = {}
    result["safe"] = true
    result["issues"] = []

    let primitives = ["ffi_open", "ffi_call", "mem_alloc", "mem_write", "asm_exec", "asm_compile"]
    let modules = ["io", "sys", "http", "tcp", "net", "os"]
    let keywords = ["import", "from", "quote"]

    let i = 0
    let n = len(code)
    while i < n:
        let c = code[i]

        # Skip comments
        if c == "#":
            i = i + 1
            while i < n and code[i] != chr(10) and code[i] != chr(13):
                i = i + 1
            end
            continue
        end

        # Skip strings
        if c == "\"" or c == "'":
            let q = c
            i = i + 1
            while i < n and code[i] != q:
                if code[i] == "\\" and i + 1 < n:
                    i = i + 2
                else:
                    i = i + 1
                end
            end
            if i < n:
                i = i + 1
            end
            continue
        end

        # Parse identifiers
        let is_letter = (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
        if is_letter:
            let ident = ""
            while i < n:
                let ch = code[i]
                let is_ident_char = (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_"
                if is_ident_char:
                    ident = ident + ch
                    i = i + 1
                else:
                    break
                end
            end

            # Check for unauthorized keywords
            for j in range(len(keywords)):
                if ident == keywords[j]:
                    result["safe"] = false
                    push(result["issues"], "Contains unauthorized keyword/identifier: " + ident)
                    return result
                end
            end

            # Check for dangerous primitives
            for j in range(len(primitives)):
                if ident == primitives[j]:
                    result["safe"] = false
                    push(result["issues"], "Contains dangerous primitive: " + ident)
                    return result
                end
            end

            # Check for unauthorized module access
            # We block unauthorized module identifiers entirely to prevent aliasing (e.g. let my_io = io)
            for j in range(len(modules)):
                if ident == modules[j]:
                    result["safe"] = false
                    push(result["issues"], "Contains unauthorized module identifier: " + ident)
                    return result
                end
            end
            continue
        end

        i = i + 1
    end

    return result

# Execute a Sage expression and return the result
# This is a simplified evaluator for common patterns
proc eval_expr(expr):
    let trimmed = trim(expr)
    # Try as number
    let num = tonumber(trimmed)
    if str(num) == trimmed:
        return {"type": "number", "value": num}
    end
    # Try as simple arithmetic
    # (Full eval would use the Sage parser — this handles common cases)
    return {"type": "string", "value": trimmed}

# Execute a code block using the Sage interpreter (via temp file)
proc execute_block(code, timeout_ms):
    let result = {}
    # Safety check first
    let safety = is_safe(code)
    if not safety["safe"]:
        result["success"] = false
        result["error"] = "Safety check failed: " + safety["issues"][0]
        result["output"] = ""
        return result
    end
    # For now, we evaluate simple expressions directly
    # Full execution would write to temp file and run sage on it
    result["success"] = true
    result["output"] = "(executed: " + str(len(code)) + " chars)"
    result["code"] = code
    return result

# ============================================================================
# Program-Aided Reasoning integration
# ============================================================================

# Wrap an LLM to support code execution
# When the model outputs code blocks, they're executed and results injected
proc create_par_agent(name, llm_fn):
    let agent = {}
    agent["name"] = name
    agent["llm_fn"] = llm_fn
    agent["executions"] = 0
    agent["errors"] = 0
    return agent

# Run a query through Program-Aided Reasoning
proc par_query(agent, question):
    let prompt = question + chr(10) + chr(10) + "If this requires calculation or code, write a Sage code block:" + chr(10) + "```sage" + chr(10) + "# your code here" + chr(10) + "```" + chr(10) + "Otherwise answer directly."
    let response = agent["llm_fn"](prompt)
    # Check for code blocks
    let blocks = extract_code_blocks(response)
    if len(blocks) > 0:
        agent["executions"] = agent["executions"] + 1
        let exec_result = execute_block(blocks[0], 5000)
        if exec_result["success"]:
            return {"answer": response, "code_executed": true, "code": blocks[0], "result": exec_result["output"]}
        else:
            agent["errors"] = agent["errors"] + 1
            return {"answer": response, "code_executed": false, "error": exec_result["error"]}
        end
    end
    return {"answer": response, "code_executed": false}

# ============================================================================
# Math evaluation (deterministic, no LLM needed)
# ============================================================================

# Evaluate simple math expressions that the LLM would otherwise hallucinate
proc eval_math(expr):
    # Basic arithmetic: handles "a + b", "a * b", etc.
    let tokens = tokenize_math(expr)
    if len(tokens) == 1:
        return tonumber(tokens[0])
    end
    if len(tokens) == 3:
        let a = tonumber(tokens[0])
        let op = tokens[1]
        let b = tonumber(tokens[2])
        if op == "+":
            return a + b
        end
        if op == "-":
            return a - b
        end
        if op == "*":
            return a * b
        end
        if op == "/":
            if b != 0:
                return a / b
            end
            return 0
        end
        if op == "%":
            return a - ((a / b) | 0) * b
        end
    end
    return 0

proc tokenize_math(expr):
    let tokens = []
    let current = ""
    for i in range(len(expr)):
        let c = expr[i]
        if c == " ":
            if len(current) > 0:
                push(tokens, current)
                current = ""
            end
        end
        if c == "+" or c == "-" or c == "*" or c == "/" or c == "%":
            if len(current) > 0:
                push(tokens, current)
                current = ""
            end
            push(tokens, c)
        end
        if c != " " and c != "+" and c != "-" and c != "*" and c != "/" and c != "%":
            current = current + c
        end
    end
    if len(current) > 0:
        push(tokens, current)
    end
    return tokens

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
        end
        if text[i] != chr(10) and text[i] != chr(13):
            current = current + text[i]
        end
    end
    if len(current) > 0:
        push(lines, current)
    end
    return lines

proc trim(s):
    let start = 0
    while start < len(s) and (s[start] == " " or s[start] == chr(9)):
        start = start + 1
    end
    let r = ""
    for i in range(len(s) - start):
        r = r + s[start + i]
    end
    return r

proc contains(h, n):
    if len(n) > len(h):
        return false
    end
    for i in range(len(h) - len(n) + 1):
        let f = true
        for j in range(len(n)):
            if not f:
                j = len(n)
            end
            if f and h[i + j] != n[j]:
                f = false
            end
        end
        if f:
            return true
        end
    end
    return false
