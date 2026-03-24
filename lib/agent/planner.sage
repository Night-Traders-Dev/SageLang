gc_disable()
# Task planning and decomposition for agentic systems
# Breaks complex goals into executable steps with dependency tracking

# ============================================================================
# Plan
# ============================================================================

let STEP_PENDING = 0
let STEP_RUNNING = 1
let STEP_DONE = 2
let STEP_FAILED = 3
let STEP_SKIPPED = 4

proc create_plan(goal):
    let plan = {}
    plan["goal"] = goal
    plan["steps"] = []
    plan["current"] = 0
    plan["status"] = "pending"
    plan["results"] = {}
    return plan

proc add_step(plan, description, tool_name, tool_args, depends_on):
    let step = {}
    step["id"] = len(plan["steps"])
    step["description"] = description
    step["tool"] = tool_name
    step["args"] = tool_args
    step["depends_on"] = depends_on
    step["status"] = 0
    step["result"] = nil
    step["error"] = nil
    push(plan["steps"], step)
    return step["id"]

proc can_execute(plan, step_id):
    let step = plan["steps"][step_id]
    if step["status"] != 0:
        return false
    let deps = step["depends_on"]
    if deps == nil:
        return true
    for i in range(len(deps)):
        let dep_step = plan["steps"][deps[i]]
        if dep_step["status"] != 2:
            return false
    return true

proc next_step(plan):
    for i in range(len(plan["steps"])):
        if can_execute(plan, i):
            return i
    return -1

proc complete_step(plan, step_id, result):
    plan["steps"][step_id]["status"] = 2
    plan["steps"][step_id]["result"] = result
    plan["results"][str(step_id)] = result
    # Check if plan is complete
    let all_done = true
    for i in range(len(plan["steps"])):
        if plan["steps"][i]["status"] == 0 or plan["steps"][i]["status"] == 1:
            all_done = false
    if all_done:
        plan["status"] = "complete"

proc fail_step(plan, step_id, error):
    plan["steps"][step_id]["status"] = 3
    plan["steps"][step_id]["error"] = error
    plan["status"] = "failed"

# Execute a plan using an agent
proc execute_plan(plan, agent):
    import agent.core
    plan["status"] = "running"
    let max_iter = len(plan["steps"]) * 2
    let iter_count = 0
    while plan["status"] == "running" and iter_count < max_iter:
        let step_id = next_step(plan)
        if step_id < 0:
            plan["status"] = "complete"
        else:
            let step = plan["steps"][step_id]
            step["status"] = 1
            if agent["verbose"]:
                print "[Plan] Step " + str(step_id) + ": " + step["description"]
            let result = core.call_tool(agent, step["tool"], step["args"])
            if result["ok"]:
                complete_step(plan, step_id, result["result"])
            else:
                fail_step(plan, step_id, result["error"])
        iter_count = iter_count + 1
    return plan

proc progress(plan):
    let done = 0
    for i in range(len(plan["steps"])):
        if plan["steps"][i]["status"] == 2:
            done = done + 1
    if len(plan["steps"]) == 0:
        return 1.0
    return done / len(plan["steps"])

proc format_plan(plan):
    let nl = chr(10)
    let out = "Goal: " + plan["goal"] + " [" + plan["status"] + "]" + nl
    for i in range(len(plan["steps"])):
        let step = plan["steps"][i]
        let marker = "[ ]"
        if step["status"] == 1:
            marker = "[>]"
        if step["status"] == 2:
            marker = "[x]"
        if step["status"] == 3:
            marker = "[!]"
        if step["status"] == 4:
            marker = "[-]"
        out = out + "  " + marker + " " + str(i) + ". " + step["description"]
        if step["tool"] != nil and len(step["tool"]) > 0:
            out = out + " (tool: " + step["tool"] + ")"
        out = out + nl
    return out

# ============================================================================
# Auto-planning (LLM generates the plan)
# ============================================================================

proc plan_prompt(goal, available_tools):
    let prompt = "Break down this goal into concrete steps:" + chr(10)
    prompt = prompt + "Goal: " + goal + chr(10) + chr(10)
    prompt = prompt + "Available tools:" + chr(10) + available_tools + chr(10)
    prompt = prompt + "Output each step as: STEP: description | tool_name | args" + chr(10)
    return prompt
