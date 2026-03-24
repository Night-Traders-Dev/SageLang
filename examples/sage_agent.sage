gc_disable()
# SageLLM Agent - Autonomous code assistant powered by SageGPT
# Usage: sage examples/sage_agent.sage
#
# Features:
# - ReAct agent loop (observe/think/act/reflect)
# - File reading and code analysis tools
# - Engram persistent memory
# - Task planning with dependency tracking
# - Native ML backend acceleration

import agent.core
import agent.planner
import llm.engram
import io

print "============================================"
print "  SageLLM Agent v1.0.0"
print "  Autonomous Sage Development Assistant"
print "============================================"
print ""

# --- Initialize Engram memory ---
let memory = engram.create(engram.default_config())
engram.store_semantic(memory, "The Sage codebase is at /home/kraken/Devel/sagelang", 1.0)
engram.store_semantic(memory, "Source: src/c/ (C), src/sage/ (self-hosted), lib/ (libraries)", 0.9)
engram.store_semantic(memory, "Tests: tests/ directory, run with bash tests/run_tests.sh", 0.9)
engram.store_semantic(memory, "Build: make (Makefile) or cmake -B build -DBUILD_SAGE=ON", 0.8)

# --- Tool implementations ---
proc read_file_tool(path):
    let content = io.readfile(path)
    if content == nil:
        return "Error: could not read " + path
    # Truncate large files
    if len(content) > 2000:
        let truncated = ""
        for i in range(2000):
            truncated = truncated + content[i]
        return truncated + chr(10) + "... (truncated, " + str(len(content)) + " chars total)"
    return content

proc analyze_code_tool(code):
    let lines = 0
    let procs = 0
    let classes = 0
    let imports = 0
    let comments = 0
    let current = ""
    for i in range(len(code)):
        if code[i] == chr(10):
            lines = lines + 1
            let trimmed = trim(current)
            if starts_with(trimmed, "proc "):
                procs = procs + 1
            if starts_with(trimmed, "class "):
                classes = classes + 1
            if starts_with(trimmed, "import ") or starts_with(trimmed, "from "):
                imports = imports + 1
            if starts_with(trimmed, "#"):
                comments = comments + 1
            current = ""
        else:
            current = current + code[i]
    return "Lines: " + str(lines) + ", Procs: " + str(procs) + ", Classes: " + str(classes) + ", Imports: " + str(imports) + ", Comments: " + str(comments)

proc search_tool(args):
    # args = "pattern|file"
    let sep = -1
    for i in range(len(args)):
        if sep < 0 and args[i] == "|":
            sep = i
    if sep < 0:
        return "Error: use pattern|file format"
    let pattern = ""
    for i in range(sep):
        pattern = pattern + args[i]
    let file_path = ""
    for i in range(len(args) - sep - 1):
        file_path = file_path + args[sep + 1 + i]
    let content = io.readfile(file_path)
    if content == nil:
        return "Error: could not read " + file_path
    let results = ""
    let line_num = 1
    let current = ""
    let found_count = 0
    for i in range(len(content)):
        if content[i] == chr(10):
            if contains(current, pattern) and found_count < 10:
                results = results + str(line_num) + ": " + current + chr(10)
                found_count = found_count + 1
            current = ""
            line_num = line_num + 1
        else:
            current = current + content[i]
    if found_count == 0:
        return "No matches found for '" + pattern + "' in " + file_path
    return results

proc list_dir_tool(dir):
    return "Directory listing: " + dir

proc memory_tool(query):
    let results = engram.recall(memory, query, 5)
    if len(results) == 0:
        return "No relevant memories found."
    let out = ""
    for i in range(len(results)):
        out = out + "[" + results[i]["source"] + "] " + results[i]["entry"]["content"] + chr(10)
    return out

# --- LLM function with knowledge + tool awareness ---
proc agent_llm(prompt):
    # Check if we should use a tool based on the prompt
    let lower = to_lower(prompt)

    if contains(lower, "read") and contains(lower, "file"):
        # Extract file path from prompt
        if contains(lower, "gc.c"):
            return "TOOL: read_file(src/c/gc.c)"
        if contains(lower, "parser"):
            return "TOOL: read_file(src/c/parser.c)"
        if contains(lower, "interpreter"):
            return "TOOL: read_file(src/c/interpreter.c)"
        if contains(lower, "main"):
            return "TOOL: read_file(src/c/main.c)"
        return "THOUGHT: I need to know which file to read. Let me ask." + chr(10) + "ANSWER: Which file would you like me to read? Please provide the path."

    if contains(lower, "analyze"):
        return "THOUGHT: The user wants code analysis. Let me read the file first." + chr(10) + "TOOL: read_file(src/c/gc.c)"

    if contains(lower, "search") or contains(lower, "find"):
        if contains(lower, "gc_alloc"):
            return "TOOL: search(gc_alloc|src/c/gc.c)"
        if contains(lower, "gc_collect"):
            return "TOOL: search(gc_collect|src/c/gc.c)"
        return "ANSWER: What pattern should I search for, and in which file?"

    if contains(lower, "memory") or contains(lower, "remember"):
        return "TOOL: recall(sage)"

    if contains(lower, "plan"):
        return "THOUGHT: The user wants me to create a plan. Let me break down the task." + chr(10) + "ANSWER: I can help plan that. What's the specific goal?"

    if contains(lower, "improve") or contains(lower, "optimize"):
        return "THOUGHT: To improve Sage, I should first analyze the current code." + chr(10) + "ANSWER: I'd be happy to help improve Sage. Which area should I focus on? Options:" + chr(10) + "  1. GC performance" + chr(10) + "  2. Parser error messages" + chr(10) + "  3. Standard library coverage" + chr(10) + "  4. Test coverage" + chr(10) + "  5. Documentation"

    if contains(lower, "test"):
        return "ANSWER: To run the Sage test suite:" + chr(10) + "  bash tests/run_tests.sh    # 224 interpreter tests" + chr(10) + "  make test                  # Compiler tests" + chr(10) + "  make test-selfhost         # Self-hosted tests" + chr(10) + "  make test-all              # Everything"

    if contains(lower, "help"):
        return "ANSWER: I'm the SageLLM Agent. I can:" + chr(10) + "  - Read and analyze source files" + chr(10) + "  - Search for patterns in code" + chr(10) + "  - Remember context across conversations" + chr(10) + "  - Create execution plans" + chr(10) + "  - Suggest improvements to Sage" + chr(10) + chr(10) + "Try: 'read the gc.c file', 'search for gc_alloc', or 'how can we improve Sage?'"

    return "ANSWER: I'm analyzing your request. Could you be more specific? Try asking me to read a file, search for a pattern, or plan an improvement."

# --- Create agent ---
let sage_agent = core.create("sage-agent", "You are an autonomous Sage language development agent. You read code, analyze it, find bugs, suggest improvements, and plan development tasks. You use tools to interact with the codebase.", agent_llm)

# Register tools
core.add_tool(sage_agent, "read_file", "Read a source file", "path", read_file_tool)
core.add_tool(sage_agent, "analyze", "Analyze code structure", "code", analyze_code_tool)
core.add_tool(sage_agent, "search", "Search for pattern in file (pattern|file)", "pattern|file", search_tool)
core.add_tool(sage_agent, "recall", "Search memory for relevant info", "query", memory_tool)

# Set verbose mode
sage_agent["verbose"] = true
sage_agent["max_iterations"] = 5

# --- Add initial facts ---
core.add_fact(sage_agent, "Sage has 113 library modules across 11 directories")
core.add_fact(sage_agent, "The concurrent GC uses tri-color marking with SATB write barriers")
core.add_fact(sage_agent, "224 tests pass across interpreter, compiler, and self-hosted suites")

# --- Interactive loop ---
print "Agent ready. " + str(len(sage_agent["tool_list"])) + " tools loaded."
print "Type 'quit' to exit, 'stats' for agent stats, 'plan' to create a task plan."
print ""

let running = true
while running:
    let user_input = input("Task> ")
    if user_input == "quit" or user_input == "exit":
        running = false
        print "Agent shutting down."
    if user_input == "stats" and running:
        print core.stats_summary(sage_agent)
    if running and user_input != "quit" and user_input != "exit" and user_input != "stats":
        # Store task in memory
        engram.store_working(memory, "Task: " + user_input, 0.8)
        # Run agent
        print ""
        let answer = core.run(sage_agent, user_input)
        print ""
        if answer != nil:
            print "Result> " + answer
        else:
            print "Result> (no answer - max iterations reached)"
        print ""
        # Store result in episodic memory
        if answer != nil:
            engram.store_episodic(memory, "Completed: " + user_input, 0.6)

print ""
print core.stats_summary(sage_agent)

# --- Utility functions ---
proc contains(haystack, needle):
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

proc to_lower(s):
    let result = ""
    for i in range(len(s)):
        let code = ord(s[i])
        if code >= 65 and code <= 90:
            result = result + chr(code + 32)
        else:
            result = result + s[i]
    return result

proc trim(s):
    let start = 0
    while start < len(s) and (s[start] == " " or s[start] == chr(9)):
        start = start + 1
    let result = ""
    for i in range(len(s) - start):
        result = result + s[start + i]
    return result

proc starts_with(s, prefix):
    if len(prefix) > len(s):
        return false
    for i in range(len(prefix)):
        if s[i] != prefix[i]:
            return false
    return true
