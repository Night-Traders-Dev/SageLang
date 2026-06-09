gc_disable()
# Agentic LLM framework
# Tools, chain-of-thought, memory, planning, and multi-agent orchestration

# ============================================================================
# Tool system
# ============================================================================

proc create_tool(name, description, fn):
    let tool = {}
    tool["name"] = name
    tool["description"] = description
    tool["fn"] = fn
    tool["call_count"] = 0
    return tool

proc create_toolbox():
    let tb = {}
    tb["tools"] = {}
    tb["tool_list"] = []
    return tb

proc register_tool(toolbox, tool):
    toolbox["tools"][tool["name"]] = tool
    push(toolbox["tool_list"], tool)

proc call_tool(toolbox, name, args):
    if not dict_has(toolbox["tools"], name):
        return {"error": "Unknown tool: " + name}
    let tool = toolbox["tools"][name]
    tool["call_count"] = tool["call_count"] + 1
    try:
        let result = tool["fn"](args)
        return {"result": result}
    catch e:
        return {"error": str(e)}

proc list_tools(toolbox):
    let descriptions = []
    for i in range(len(toolbox["tool_list"])):
        let t = toolbox["tool_list"][i]
        let d = {}
        d["name"] = t["name"]
        d["description"] = t["description"]
        push(descriptions, d)
    return descriptions

# Format tool descriptions for LLM prompt
proc tools_prompt(toolbox):
    let result = "Available tools:" + chr(10)
    for i in range(len(toolbox["tool_list"])):
        let t = toolbox["tool_list"][i]
        result = result + "- " + t["name"] + ": " + t["description"] + chr(10)
    return result

# ============================================================================
# Memory system (short-term + long-term)
# ============================================================================

proc create_memory(max_short_term):
    let mem = {}
    mem["short_term"] = []
    mem["long_term"] = {}
    mem["max_short_term"] = max_short_term
    mem["facts"] = []
    return mem

proc add_short_term(memory, entry):
    push(memory["short_term"], entry)
    if len(memory["short_term"]) > memory["max_short_term"]:
        # Remove oldest
        let new_st = []
        for i in range(len(memory["short_term"]) - 1):
            push(new_st, memory["short_term"][i + 1])
        memory["short_term"] = new_st

proc add_long_term(memory, key, value):
    memory["long_term"][key] = value

proc get_long_term(memory, key):
    if dict_has(memory["long_term"], key):
        return memory["long_term"][key]
    return nil

proc add_fact(memory, fact):
    push(memory["facts"], fact)

proc get_facts(memory):
    return memory["facts"]

proc memory_context(memory):
    let ctx = ""
    if len(memory["facts"]) > 0:
        ctx = ctx + "Known facts:" + chr(10)
        for i in range(len(memory["facts"])):
            ctx = ctx + "- " + memory["facts"][i] + chr(10)
    if len(memory["short_term"]) > 0:
        ctx = ctx + "Recent context:" + chr(10)
        for i in range(len(memory["short_term"])):
            ctx = ctx + "- " + str(memory["short_term"][i]) + chr(10)
    return ctx

# ============================================================================
# Agent
# ============================================================================

proc create_agent(name, system_prompt):
    let agent = {}
    agent["name"] = name
    agent["system_prompt"] = system_prompt
    agent["toolbox"] = create_toolbox()
    agent["memory"] = create_memory(20)
    agent["history"] = []
    agent["max_iterations"] = 10
    agent["verbose"] = false
    agent["total_tool_calls"] = 0
    agent["total_turns"] = 0
    return agent

proc add_tool(agent, name, description, fn):
    register_tool(agent["toolbox"], create_tool(name, description, fn))

# Record a turn in conversation history
proc add_turn(agent, role, content):
    let turn = {}
    turn["role"] = role
    turn["content"] = content
    push(agent["history"], turn)
    agent["total_turns"] = agent["total_turns"] + 1

# Build the full prompt for the LLM
proc build_prompt(agent, user_message):
    let prompt = agent["system_prompt"] + chr(10) + chr(10)
    # Add tool descriptions
    let tool_desc = tools_prompt(agent["toolbox"])
    if len(agent["toolbox"]["tool_list"]) > 0:
        prompt = prompt + tool_desc + chr(10)
    # Add memory context
    let mem_ctx = memory_context(agent["memory"])
    if len(mem_ctx) > 0:
        prompt = prompt + mem_ctx + chr(10)
    # Add conversation history
    let history = agent["history"]
    for i in range(len(history)):
        let turn = history[i]
        prompt = prompt + turn["role"] + ": " + turn["content"] + chr(10)
    prompt = prompt + "user: " + user_message + chr(10)
    prompt = prompt + "assistant: "
    return prompt

# ============================================================================
# Chain-of-thought reasoning
# ============================================================================

proc create_reasoning_chain():
    let chain = {}
    chain["steps"] = []
    chain["conclusion"] = ""
    return chain

proc add_thought(chain, thought):
    let step = {}
    step["type"] = "thought"
    step["content"] = thought
    push(chain["steps"], step)

proc add_observation(chain, observation):
    let step = {}
    step["type"] = "observation"
    step["content"] = observation
    push(chain["steps"], step)

proc add_action(chain, action, result):
    let step = {}
    step["type"] = "action"
    step["action"] = action
    step["result"] = result
    push(chain["steps"], step)

proc set_conclusion(chain, conclusion):
    chain["conclusion"] = conclusion

proc format_chain(chain):
    let result = ""
    for i in range(len(chain["steps"])):
        let step = chain["steps"][i]
        if step["type"] == "thought":
            result = result + "Thought: " + step["content"] + chr(10)
        if step["type"] == "observation":
            result = result + "Observation: " + step["content"] + chr(10)
        if step["type"] == "action":
            result = result + "Action: " + step["action"] + chr(10)
            result = result + "Result: " + str(step["result"]) + chr(10)
    if len(chain["conclusion"]) > 0:
        result = result + "Conclusion: " + chain["conclusion"] + chr(10)
    return result

# ============================================================================
# Multi-agent orchestration
# ============================================================================

proc create_team(name):
    let team = {}
    team["name"] = name
    team["agents"] = {}
    team["agent_list"] = []
    team["coordinator"] = nil
    team["shared_memory"] = create_memory(50)
    team["message_log"] = []
    return team

proc add_agent(team, agent):
    team["agents"][agent["name"]] = agent
    push(team["agent_list"], agent)

proc set_coordinator(team, agent_name):
    team["coordinator"] = agent_name

# Send a message between agents
proc send_message(team, from_name, to_name, content):
    let msg = {}
    msg["from"] = from_name
    msg["to"] = to_name
    msg["content"] = content
    push(team["message_log"], msg)
    # Add to recipient's memory
    if dict_has(team["agents"], to_name):
        let agent = team["agents"][to_name]
        add_short_term(agent["memory"], "Message from " + from_name + ": " + content)

proc team_summary(team):
    let result = "Team: " + team["name"] + chr(10)
    result = result + "Agents: " + str(len(team["agent_list"])) + chr(10)
    for i in range(len(team["agent_list"])):
        let a = team["agent_list"][i]
        result = result + "  - " + a["name"] + " (" + str(a["total_turns"]) + " turns, " + str(a["total_tool_calls"]) + " tool calls)" + chr(10)
    result = result + "Messages: " + str(len(team["message_log"])) + chr(10)
    return result

# ============================================================================
# Planning
# ============================================================================

proc create_plan(goal):
    let plan = {}
    plan["goal"] = goal
    plan["steps"] = []
    plan["current_step"] = 0
    plan["status"] = "pending"
    return plan

proc add_plan_step(plan, description, agent_name):
    let step = {}
    step["description"] = description
    step["agent"] = agent_name
    step["status"] = "pending"
    step["result"] = nil
    push(plan["steps"], step)

proc advance_plan(plan, result):
    if plan["current_step"] < len(plan["steps"]):
        plan["steps"][plan["current_step"]]["status"] = "complete"
        plan["steps"][plan["current_step"]]["result"] = result
        plan["current_step"] = plan["current_step"] + 1
        if plan["current_step"] >= len(plan["steps"]):
            plan["status"] = "complete"
        else:
            plan["status"] = "in_progress"
    return plan

proc plan_progress(plan):
    if len(plan["steps"]) == 0:
        return 0
    return plan["current_step"] / len(plan["steps"])

proc format_plan(plan):
    let result = "Goal: " + plan["goal"] + " (" + plan["status"] + ")" + chr(10)
    for i in range(len(plan["steps"])):
        let step = plan["steps"][i]
        let marker = "[ ]"
        if step["status"] == "complete":
            marker = "[x]"
        if i == plan["current_step"] and plan["status"] == "in_progress":
            marker = "[>]"
        result = result + marker + " " + step["description"]
        if len(step["agent"]) > 0:
            result = result + " (@" + step["agent"] + ")"
        result = result + chr(10)
    return result
