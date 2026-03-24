gc_disable()
# Multi-agent router and orchestrator
# Routes tasks to specialized agents based on capability matching

# ============================================================================
# Router
# ============================================================================

proc create_router():
    let router = {}
    router["agents"] = {}
    router["agent_list"] = []
    router["routes"] = []
    router["default_agent"] = nil
    router["message_log"] = []
    router["total_routed"] = 0
    return router

# Register an agent with capability tags
proc register(router, agent, capabilities):
    let entry = {}
    entry["agent"] = agent
    entry["capabilities"] = capabilities
    entry["tasks_handled"] = 0
    router["agents"][agent["name"]] = entry
    push(router["agent_list"], entry)

# Add a routing rule: pattern -> agent_name
proc add_route(router, pattern, agent_name):
    let route = {}
    route["pattern"] = pattern
    route["agent_name"] = agent_name
    push(router["routes"], route)

# Set default agent for unmatched queries
proc set_default(router, agent_name):
    router["default_agent"] = agent_name

# Route a message to the best agent
proc route(router, message):
    # Check explicit routes first
    for i in range(len(router["routes"])):
        let r = router["routes"][i]
        if contains(message, r["pattern"]):
            router["total_routed"] = router["total_routed"] + 1
            let entry = router["agents"][r["agent_name"]]
            entry["tasks_handled"] = entry["tasks_handled"] + 1
            log_message(router, "router", r["agent_name"], message)
            return entry["agent"]
    # Check capabilities
    let best_agent = nil
    let best_score = 0
    for i in range(len(router["agent_list"])):
        let entry = router["agent_list"][i]
        let score = capability_match(message, entry["capabilities"])
        if score > best_score:
            best_score = score
            best_agent = entry
    if best_agent != nil:
        router["total_routed"] = router["total_routed"] + 1
        best_agent["tasks_handled"] = best_agent["tasks_handled"] + 1
        log_message(router, "router", best_agent["agent"]["name"], message)
        return best_agent["agent"]
    # Default
    if router["default_agent"] != nil and dict_has(router["agents"], router["default_agent"]):
        let entry = router["agents"][router["default_agent"]]
        entry["tasks_handled"] = entry["tasks_handled"] + 1
        return entry["agent"]
    return nil

# Score how well a message matches capabilities
proc capability_match(message, capabilities):
    let score = 0
    for i in range(len(capabilities)):
        if contains(message, capabilities[i]):
            score = score + 1
    return score

# ============================================================================
# Message passing
# ============================================================================

proc log_message(router, from_name, to_name, content):
    let msg = {}
    msg["from"] = from_name
    msg["to"] = to_name
    msg["content"] = content
    push(router["message_log"], msg)

proc send_to(router, from_agent, to_name, message):
    log_message(router, from_agent["name"], to_name, message)
    if dict_has(router["agents"], to_name):
        import agent.core
        let target = router["agents"][to_name]["agent"]
        return core.run(target, message)
    return nil

# ============================================================================
# Pipeline (chain agents in sequence)
# ============================================================================

proc create_pipeline(name):
    let pipe = {}
    pipe["name"] = name
    pipe["stages"] = []
    return pipe

proc add_stage(pipeline, agent_name, transform_fn):
    let stage = {}
    stage["agent_name"] = agent_name
    stage["transform"] = transform_fn
    push(pipeline["stages"], stage)

proc run_pipeline(pipeline, router, initial_input):
    let current = initial_input
    for i in range(len(pipeline["stages"])):
        let stage = pipeline["stages"][i]
        let agent_entry = router["agents"][stage["agent_name"]]
        if agent_entry == nil:
            return {"error": "Agent not found: " + stage["agent_name"]}
        import agent.core
        let result = core.run(agent_entry["agent"], current)
        if stage["transform"] != nil:
            current = stage["transform"](result)
        else:
            current = result
    return current

# ============================================================================
# Utilities
# ============================================================================

proc contains(haystack, needle):
    if len(needle) == 0:
        return true
    if len(needle) > len(haystack):
        return false
    let lower_h = to_lower(haystack)
    let lower_n = to_lower(needle)
    for i in range(len(lower_h) - len(lower_n) + 1):
        let found = true
        for j in range(len(lower_n)):
            if not found:
                j = len(lower_n)
            if found and lower_h[i + j] != lower_n[j]:
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

proc router_stats(router):
    let nl = chr(10)
    let out = "Router stats:" + nl
    out = out + "  Total routed: " + str(router["total_routed"]) + nl
    out = out + "  Agents: " + str(len(router["agent_list"])) + nl
    for i in range(len(router["agent_list"])):
        let entry = router["agent_list"][i]
        out = out + "    " + entry["agent"]["name"] + ": " + str(entry["tasks_handled"]) + " tasks" + nl
    out = out + "  Messages: " + str(len(router["message_log"])) + nl
    return out
