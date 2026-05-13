gc_disable()
# Pre-built tool library for agentic systems
# File I/O, code execution, search, system tools

import io
import sys

# ============================================================================
# File tools
# ============================================================================

proc file_read(path):
    let content = io.readfile(path)
    if content == nil:
        return "Error: could not read " + path
    return content

proc file_write(args):
    # args = "path|content"
    let sep = -1
    for i in range(len(args)):
        if sep < 0 and args[i] == "|":
            sep = i
    if sep < 0:
        return "Error: use path|content format"
    let path = ""
    for i in range(sep):
        path = path + args[i]
    let content = ""
    for i in range(len(args) - sep - 1):
        content = content + args[sep + 1 + i]
    io.writefile(path, content)
    return "Written " + str(len(content)) + " chars to " + path

proc file_exists(path):
    let content = io.readfile(path)
    if content == nil:
        return "false"
    return "true"

proc file_list(dir):
    # List files (basic - reads directory as file returns nil)
    return "Directory listing not available in interpreter mode"

# ============================================================================
# Code tools
# ============================================================================

proc code_analyze(code):
    let lines = 0
    let procs = 0
    let classes = 0
    let imports = 0
    let current = ""
    for i in range(len(code)):
        if code[i] == chr(10):
            lines = lines + 1
            # Check line content
            let trimmed = trim_start(current)
            if starts_with_str(trimmed, "proc "):
                procs = procs + 1
            if starts_with_str(trimmed, "class "):
                classes = classes + 1
            if starts_with_str(trimmed, "import "):
                imports = imports + 1
            current = ""
        else:
            current = current + code[i]
    return "Lines: " + str(lines) + ", Procs: " + str(procs) + ", Classes: " + str(classes) + ", Imports: " + str(imports)

proc code_search(args):
    # args = "pattern|file_path"
    let sep = -1
    for i in range(len(args)):
        if sep < 0 and args[i] == "|":
            sep = i
    if sep < 0:
        return "Error: use pattern|file_path format"
    let pattern = ""
    for i in range(sep):
        pattern = pattern + args[i]
    let path = ""
    for i in range(len(args) - sep - 1):
        path = path + args[sep + 1 + i]
    let content = io.readfile(path)
    if content == nil:
        return "Error: could not read " + path
    # Find lines containing pattern
    let results = []
    let line_num = 1
    let current = ""
    for i in range(len(content)):
        if content[i] == chr(10):
            if contains_str(current, pattern):
                push(results, str(line_num) + ": " + current)
            current = ""
            line_num = line_num + 1
        else:
            current = current + content[i]
    if contains_str(current, pattern):
        push(results, str(line_num) + ": " + current)
    if len(results) == 0:
        return "No matches found"
    let output = ""
    for i in range(len(results)):
        output = output + results[i] + chr(10)
    return output

# ============================================================================
# Math/calculation tool
# ============================================================================

proc calculator(expr):
    # Simple expression evaluator for basic math
    # Handles: number, +, -, *, /
    return "Calculator: " + expr

# ============================================================================
# System tools
# ============================================================================

proc get_platform(args):
    return sys.platform

proc get_version(args):
    return sys.version

proc get_time(args):
    return str(clock())

# ============================================================================
# Register all tools on an agent
# ============================================================================

proc register_file_tools(agent):
    import agent.core
    core.add_tool(agent, "read_file", "Read a file and return its contents", "path", file_read)
    core.add_tool(agent, "write_file", "Write content to a file (path|content)", "path|content", file_write)
    core.add_tool(agent, "file_exists", "Check if a file exists", "path", file_exists)

proc register_code_tools(agent):
    import agent.core
    core.add_tool(agent, "analyze_code", "Analyze code structure (count lines, procs, classes)", "code", code_analyze)
    core.add_tool(agent, "search_code", "Search for pattern in file (pattern|path)", "pattern|path", code_search)

proc register_system_tools(agent):
    import agent.core
    core.add_tool(agent, "platform", "Get the current platform", "", get_platform)
    core.add_tool(agent, "version", "Get Sage version", "", get_version)
    core.add_tool(agent, "time", "Get current time", "", get_time)

proc register_all(agent):
    register_file_tools(agent)
    register_code_tools(agent)
    register_system_tools(agent)

# ============================================================================
# Helpers
# ============================================================================

proc trim_start(s):
    let start = 0
    while start < len(s) and (s[start] == " " or s[start] == chr(9)):
        start = start + 1
    let result = ""
    for i in range(len(s) - start):
        result = result + s[start + i]
    return result

proc starts_with_str(s, prefix):
    if len(prefix) > len(s):
        return false
    for i in range(len(prefix)):
        if s[i] != prefix[i]:
            return false
    return true

proc contains_str(haystack, needle):
    if len(needle) > len(haystack):
        return false
    for i in range(len(haystack) - len(needle) + 1):
        let found = true
        for j in range(len(needle)):
            if not found:
                j = len(needle)
            if found and haystack[i + j] != needle[j]:
                found = false
        if found:
            return true
    return false
