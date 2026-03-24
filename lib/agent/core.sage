gc_disable()
# Agentic AI framework core
# Autonomous agent loop: observe -> think -> act -> reflect
# Works with any LLM backend (SageGPT, GPT-2, or external API)

# Agent states
let STATE_IDLE = 0
let STATE_THINKING = 1
let STATE_ACTING = 2
let STATE_REFLECTING = 3
let STATE_WAITING = 4
let STATE_DONE = 5
let STATE_ERROR = 6

proc state_name(s):
    if s == 0:
        return "idle"
    if s == 1:
        return "thinking"
    if s == 2:
        return "acting"
    if s == 3:
        return "reflecting"
    if s == 4:
        return "waiting"
    if s == 5:
        return "done"
    if s == 6:
        return "error"
    return "unknown"

# ============================================================================
# Agent creation
# ============================================================================

proc create(name, system_prompt, llm_fn):
    let agent = {}
    agent["name"] = name
    agent["system_prompt"] = system_prompt
    agent["llm_fn"] = llm_fn
    agent["state"] = 0
    agent["tools"] = {}
    agent["tool_list"] = []
    agent["memory"] = []
    agent["facts"] = []
    agent["history"] = []
    agent["scratchpad"] = []
    agent["max_iterations"] = 10
    agent["iteration"] = 0
    agent["verbose"] = false
    agent["on_think"] = nil
    agent["on_act"] = nil
    agent["on_reflect"] = nil
    agent["stats"] = {}
    agent["stats"]["tool_calls"] = 0
    agent["stats"]["llm_calls"] = 0
    agent["stats"]["tokens_in"] = 0
    agent["stats"]["tokens_out"] = 0
    agent["stats"]["errors"] = 0
    return agent

# ============================================================================
# Tool management
# ============================================================================

proc add_tool(agent, name, description, param_desc, fn):
    let tool = {}
    tool["name"] = name
    tool["description"] = description
    tool["params"] = param_desc
    tool["fn"] = fn
    tool["calls"] = 0
    agent["tools"][name] = tool
    push(agent["tool_list"], tool)

proc remove_tool(agent, name):
    if dict_has(agent["tools"], name):
        dict_delete(agent["tools"], name)
        let new_list = []
        for i in range(len(agent["tool_list"])):
            if agent["tool_list"][i]["name"] != name:
                push(new_list, agent["tool_list"][i])
        agent["tool_list"] = new_list

proc call_tool(agent, name, args):
    if not dict_has(agent["tools"], name):
        agent["stats"]["errors"] = agent["stats"]["errors"] + 1
        return {"ok": false, "error": "Unknown tool: " + name}
    let tool = agent["tools"][name]
    tool["calls"] = tool["calls"] + 1
    agent["stats"]["tool_calls"] = agent["stats"]["tool_calls"] + 1
    try:
        let result = tool["fn"](args)
        return {"ok": true, "result": result}
    catch e:
        agent["stats"]["errors"] = agent["stats"]["errors"] + 1
        return {"ok": false, "error": str(e)}

proc tools_description(agent):
    let desc = ""
    for i in range(len(agent["tool_list"])):
        let t = agent["tool_list"][i]
        desc = desc + "- " + t["name"] + "(" + t["params"] + "): " + t["description"] + chr(10)
    return desc

# ============================================================================
# Memory
# ============================================================================

proc remember(agent, content):
    push(agent["memory"], content)

proc add_fact(agent, fact):
    push(agent["facts"], fact)

proc get_context(agent):
    let ctx = ""
    if len(agent["facts"]) > 0:
        ctx = ctx + "Facts:" + chr(10)
        for i in range(len(agent["facts"])):
            ctx = ctx + "  - " + agent["facts"][i] + chr(10)
    if len(agent["memory"]) > 0:
        ctx = ctx + "Memory:" + chr(10)
        let start = 0
        if len(agent["memory"]) > 10:
            start = len(agent["memory"]) - 10
        for i in range(len(agent["memory"]) - start):
            ctx = ctx + "  - " + str(agent["memory"][start + i]) + chr(10)
    return ctx

# ============================================================================
# Scratchpad (chain-of-thought working space)
# ============================================================================

proc think(agent, thought):
    let entry = {}
    entry["type"] = "thought"
    entry["content"] = thought
    push(agent["scratchpad"], entry)
    if agent["verbose"]:
        print "[" + agent["name"] + " thinks] " + thought

proc observe(agent, observation):
    let entry = {}
    entry["type"] = "observation"
    entry["content"] = observation
    push(agent["scratchpad"], entry)
    if agent["verbose"]:
        print "[" + agent["name"] + " observes] " + observation

proc act(agent, action, result):
    let entry = {}
    entry["type"] = "action"
    entry["action"] = action
    entry["result"] = result
    push(agent["scratchpad"], entry)
    if agent["verbose"]:
        print "[" + agent["name"] + " acts] " + action + " -> " + str(result)

proc reflect(agent, reflection):
    let entry = {}
    entry["type"] = "reflection"
    entry["content"] = reflection
    push(agent["scratchpad"], entry)
    if agent["verbose"]:
        print "[" + agent["name"] + " reflects] " + reflection

# ============================================================================
# Prompt building
# ============================================================================

proc build_prompt(agent, user_input):
    let prompt = agent["system_prompt"] + chr(10) + chr(10)
    # Tools
    if len(agent["tool_list"]) > 0:
        prompt = prompt + "You have access to these tools:" + chr(10)
        prompt = prompt + tools_description(agent) + chr(10)
        prompt = prompt + "To use a tool, write: TOOL: tool_name(args)" + chr(10)
        prompt = prompt + "When done, write: ANSWER: your final answer" + chr(10) + chr(10)
    # Context
    let ctx = get_context(agent)
    if len(ctx) > 0:
        prompt = prompt + ctx + chr(10)
    # Scratchpad
    if len(agent["scratchpad"]) > 0:
        prompt = prompt + "Scratchpad:" + chr(10)
        for i in range(len(agent["scratchpad"])):
            let entry = agent["scratchpad"][i]
            if entry["type"] == "thought":
                prompt = prompt + "Thought: " + entry["content"] + chr(10)
            if entry["type"] == "observation":
                prompt = prompt + "Observation: " + entry["content"] + chr(10)
            if entry["type"] == "action":
                prompt = prompt + "Action: " + entry["action"] + " -> " + str(entry["result"]) + chr(10)
            if entry["type"] == "reflection":
                prompt = prompt + "Reflection: " + entry["content"] + chr(10)
        prompt = prompt + chr(10)
    # History
    for i in range(len(agent["history"])):
        let h = agent["history"][i]
        prompt = prompt + h["role"] + ": " + h["content"] + chr(10)
    prompt = prompt + "user: " + user_input + chr(10)
    prompt = prompt + "assistant: "
    return prompt

# ============================================================================
# LLM call
# ============================================================================

proc call_llm(agent, prompt):
    agent["stats"]["llm_calls"] = agent["stats"]["llm_calls"] + 1
    agent["stats"]["tokens_in"] = agent["stats"]["tokens_in"] + ((len(prompt) + 3) / 4) | 0
    let response = agent["llm_fn"](prompt)
    agent["stats"]["tokens_out"] = agent["stats"]["tokens_out"] + ((len(response) + 3) / 4) | 0
    return response

# ============================================================================
# Parse LLM response for tool calls
# ============================================================================

proc parse_response(response):
    let result = {}
    result["tool_call"] = nil
    result["answer"] = nil
    result["thought"] = nil
    result["raw"] = response
    # Check for TOOL: prefix
    let lines = split_lines(response)
    for i in range(len(lines)):
        let line = lines[i]
        if starts_with(line, "TOOL: "):
            let call_str = ""
            for j in range(len(line) - 6):
                call_str = call_str + line[6 + j]
            result["tool_call"] = parse_tool_call(call_str)
        if starts_with(line, "ANSWER: "):
            let ans = ""
            for j in range(len(line) - 8):
                ans = ans + line[8 + j]
            result["answer"] = ans
        if starts_with(line, "THOUGHT: ") or starts_with(line, "Thought: "):
            let th = ""
            let off = 9
            if starts_with(line, "THOUGHT: "):
                off = 9
            for j in range(len(line) - off):
                th = th + line[off + j]
            result["thought"] = th
    return result

proc parse_tool_call(call_str):
    # Parse "tool_name(args)"
    let paren_pos = -1
    for i in range(len(call_str)):
        if paren_pos < 0 and call_str[i] == "(":
            paren_pos = i
    if paren_pos < 0:
        return {"name": call_str, "args": ""}
    let name = ""
    for i in range(paren_pos):
        name = name + call_str[i]
    let args = ""
    for i in range(len(call_str) - paren_pos - 2):
        args = args + call_str[paren_pos + 1 + i]
    return {"name": name, "args": args}

# ============================================================================
# Agent execution loop (ReAct pattern)
# ============================================================================

proc run(agent, user_input):
    agent["state"] = 1
    agent["iteration"] = 0
    agent["scratchpad"] = []
    let final_answer = nil

    while agent["iteration"] < agent["max_iterations"] and final_answer == nil:
        agent["iteration"] = agent["iteration"] + 1

        # 1. Build prompt and call LLM
        let prompt = build_prompt(agent, user_input)
        let response = call_llm(agent, prompt)

        # 2. Parse response
        let parsed = parse_response(response)

        # 3. Handle thought
        if parsed["thought"] != nil:
            think(agent, parsed["thought"])

        # 4. Handle tool call
        if parsed["tool_call"] != nil:
            agent["state"] = 2
            let tc = parsed["tool_call"]
            let tool_result = call_tool(agent, tc["name"], tc["args"])
            if tool_result["ok"]:
                observe(agent, str(tool_result["result"]))
                act(agent, tc["name"] + "(" + tc["args"] + ")", tool_result["result"])
            else:
                observe(agent, "Error: " + tool_result["error"])

        # 5. Handle final answer
        if parsed["answer"] != nil:
            final_answer = parsed["answer"]
            agent["state"] = 5

        # 6. If no tool call and no answer, treat entire response as answer
        if parsed["tool_call"] == nil and parsed["answer"] == nil and parsed["thought"] == nil:
            final_answer = response
            agent["state"] = 5

    # Record in history
    let user_turn = {}
    user_turn["role"] = "user"
    user_turn["content"] = user_input
    push(agent["history"], user_turn)
    let asst_turn = {}
    asst_turn["role"] = "assistant"
    if final_answer != nil:
        asst_turn["content"] = final_answer
    else:
        asst_turn["content"] = "(max iterations reached)"
        agent["state"] = 6
    push(agent["history"], asst_turn)

    return final_answer

# ============================================================================
# Utilities
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

proc starts_with(s, prefix):
    if len(prefix) > len(s):
        return false
    for i in range(len(prefix)):
        if s[i] != prefix[i]:
            return false
    return true

proc reset(agent):
    agent["state"] = 0
    agent["iteration"] = 0
    agent["scratchpad"] = []
    agent["history"] = []
    agent["memory"] = []

proc stats_summary(agent):
    let s = agent["stats"]
    let nl = chr(10)
    return "Agent: " + agent["name"] + nl + "LLM calls: " + str(s["llm_calls"]) + nl + "Tool calls: " + str(s["tool_calls"]) + nl + "Errors: " + str(s["errors"]) + nl + "Tokens in: ~" + str(s["tokens_in"]) + nl + "Tokens out: ~" + str(s["tokens_out"]) + nl
