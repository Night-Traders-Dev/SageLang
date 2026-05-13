gc_disable()
# Typed interfaces and bounded tool execution
# Forces agents to communicate via strict schemas
# Prevents unconstrained execution and catastrophic errors

# ============================================================================
# Schema types
# ============================================================================

let TYPE_STRING = "string"
let TYPE_NUMBER = "number"
let TYPE_BOOL = "bool"
let TYPE_ARRAY = "array"
let TYPE_DICT = "dict"
let TYPE_ANY = "any"

# Define a parameter schema
proc param(name, param_type, required, description):
    let p = {}
    p["name"] = name
    p["type"] = param_type
    p["required"] = required
    p["description"] = description
    p["default"] = nil
    return p

proc param_with_default(name, param_type, description, default_val):
    let p = param(name, param_type, false, description)
    p["default"] = default_val
    return p

# Define a tool schema (bounded execution interface)
proc tool_schema(name, description, params, return_type):
    let s = {}
    s["name"] = name
    s["description"] = description
    s["params"] = params
    s["return_type"] = return_type
    return s

# ============================================================================
# Schema validation
# ============================================================================

# Validate a value matches a type
proc validate_type(value, expected_type):
    if expected_type == "any":
        return true
    let actual = type(value)
    if expected_type == "string":
        return actual == "string"
    if expected_type == "number":
        return actual == "number"
    if expected_type == "bool":
        return actual == "bool"
    if expected_type == "array":
        return actual == "array"
    if expected_type == "dict":
        return actual == "dict"
    return false

# Validate arguments against a tool schema
proc validate_args(schema, args):
    let errors = []
    let params = schema["params"]
    for i in range(len(params)):
        let p = params[i]
        if dict_has(args, p["name"]):
            let val = args[p["name"]]
            if not validate_type(val, p["type"]):
                push(errors, p["name"] + ": expected " + p["type"] + ", got " + type(val))
        else:
            if p["required"]:
                push(errors, p["name"] + ": required parameter missing")
    let result = {}
    result["valid"] = len(errors) == 0
    result["errors"] = errors
    return result

# Apply defaults for missing optional parameters
proc apply_defaults(schema, args):
    let result = {}
    let keys = dict_keys(args)
    for i in range(len(keys)):
        result[keys[i]] = args[keys[i]]
    let params = schema["params"]
    for i in range(len(params)):
        let p = params[i]
        if not dict_has(result, p["name"]) and p["default"] != nil:
            result[p["name"]] = p["default"]
    return result

# ============================================================================
# Bounded tool registry
# ============================================================================

proc create_registry():
    let reg = {}
    reg["tools"] = {}
    reg["schemas"] = {}
    reg["call_log"] = []
    reg["total_calls"] = 0
    reg["total_errors"] = 0
    return reg

# Register a tool with its schema and implementation
proc register(reg, schema, fn):
    reg["tools"][schema["name"]] = fn
    reg["schemas"][schema["name"]] = schema

# Execute a tool with schema validation
proc execute(reg, tool_name, args):
    if not dict_has(reg["tools"], tool_name):
        reg["total_errors"] = reg["total_errors"] + 1
        return {"success": false, "error": "Unknown tool: " + tool_name}
    let schema = reg["schemas"][tool_name]
    # Validate arguments
    let validation = validate_args(schema, args)
    if not validation["valid"]:
        reg["total_errors"] = reg["total_errors"] + 1
        let err_msg = ""
        for i in range(len(validation["errors"])):
            if i > 0:
                err_msg = err_msg + "; "
            err_msg = err_msg + validation["errors"][i]
        let log_entry = {}
        log_entry["tool"] = tool_name
        log_entry["success"] = false
        log_entry["error"] = "Validation: " + err_msg
        push(reg["call_log"], log_entry)
        return {"success": false, "error": "Schema validation failed: " + err_msg}
    # Apply defaults
    let final_args = apply_defaults(schema, args)
    # Execute
    reg["total_calls"] = reg["total_calls"] + 1
    try:
        let result = reg["tools"][tool_name](final_args)
        let log_entry = {}
        log_entry["tool"] = tool_name
        log_entry["success"] = true
        push(reg["call_log"], log_entry)
        return {"success": true, "result": result}
    catch e:
        reg["total_errors"] = reg["total_errors"] + 1
        let log_entry = {}
        log_entry["tool"] = tool_name
        log_entry["success"] = false
        log_entry["error"] = str(e)
        push(reg["call_log"], log_entry)
        return {"success": false, "error": str(e)}

# ============================================================================
# Pre-built bounded tool schemas
# ============================================================================

proc file_read_schema():
    return tool_schema("read_file", "Read contents of a file at a given path", [param("path", "string", true, "File path to read")], "string")

proc file_write_schema():
    return tool_schema("write_file", "Write content to a file", [param("path", "string", true, "File path"), param("content", "string", true, "Content to write")], "string")

proc search_schema():
    return tool_schema("search", "Search for a pattern in a file", [param("pattern", "string", true, "Search pattern"), param("path", "string", true, "File to search")], "string")

proc analyze_schema():
    return tool_schema("analyze", "Analyze code structure", [param("code", "string", true, "Code to analyze")], "dict")

# List available tools with descriptions and schemas
proc list_tools(reg):
    let tools = []
    let keys = dict_keys(reg["schemas"])
    for i in range(len(keys)):
        let s = reg["schemas"][keys[i]]
        let desc = {}
        desc["name"] = s["name"]
        desc["description"] = s["description"]
        desc["params"] = []
        for j in range(len(s["params"])):
            let p = s["params"][j]
            let pd = {}
            pd["name"] = p["name"]
            pd["type"] = p["type"]
            pd["required"] = p["required"]
            push(desc["params"], pd)
        push(tools, desc)
    return tools

# Format tool list for LLM prompt
proc tools_prompt(reg):
    let tools = list_tools(reg)
    let result = "Available tools:" + chr(10)
    for i in range(len(tools)):
        let t = tools[i]
        result = result + "  " + t["name"] + "("
        for j in range(len(t["params"])):
            if j > 0:
                result = result + ", "
            result = result + t["params"][j]["name"] + ": " + t["params"][j]["type"]
        result = result + ") - " + t["description"] + chr(10)
    return result
