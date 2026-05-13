gc_disable()
# Supervisor-Worker Agent Architecture
# The Supervisor (control plane) owns global state, plans workflows,
# routes to specialist Workers, validates transitions, handles timeouts.
# Workers are intentionally narrow in scope — one task type each.

# ============================================================================
# Worker definition
# ============================================================================

proc create_worker(name, role, llm_fn, tools):
    let w = {}
    w["name"] = name
    w["role"] = role
    w["llm_fn"] = llm_fn
    w["tools"] = tools
    w["tool_names"] = []
    for i in range(len(tools)):
        push(w["tool_names"], tools[i]["name"])
    w["tasks_completed"] = 0
    w["tasks_failed"] = 0
    w["total_tokens"] = 0
    w["active"] = false
    return w

proc create_tool(name, description, param_schema, fn):
    let t = {}
    t["name"] = name
    t["description"] = description
    t["schema"] = param_schema
    t["fn"] = fn
    t["calls"] = 0
    return t

# Execute a task on a worker with its LLM + tools
proc worker_execute(worker, task, max_attempts):
    worker["active"] = true
    let attempts = 0
    let result = nil
    let errors = []
    while attempts < max_attempts and result == nil:
        attempts = attempts + 1
        try:
            let response = worker["llm_fn"](task)
            result = response
            worker["tasks_completed"] = worker["tasks_completed"] + 1
        catch e:
            push(errors, str(e))
            worker["tasks_failed"] = worker["tasks_failed"] + 1
    worker["active"] = false
    let outcome = {}
    outcome["result"] = result
    outcome["attempts"] = attempts
    outcome["errors"] = errors
    outcome["success"] = result != nil
    outcome["worker"] = worker["name"]
    return outcome

# ============================================================================
# Supervisor (Control Plane)
# ============================================================================

proc create_supervisor(name, llm_fn):
    let sup = {}
    sup["name"] = name
    sup["llm_fn"] = llm_fn
    sup["workers"] = {}
    sup["worker_list"] = []
    sup["global_state"] = {}
    sup["workflow"] = []
    sup["history"] = []
    sup["current_step"] = 0
    sup["status"] = "idle"
    sup["max_retries"] = 3
    sup["timeout_steps"] = 50
    sup["validation_fn"] = nil
    sup["on_step_complete"] = nil
    sup["on_error"] = nil
    sup["stats"] = {}
    sup["stats"]["tasks_dispatched"] = 0
    sup["stats"]["tasks_succeeded"] = 0
    sup["stats"]["tasks_failed"] = 0
    sup["stats"]["total_steps"] = 0
    sup["stats"]["retries"] = 0
    return sup

# Register a specialist worker
proc add_worker(sup, worker):
    sup["workers"][worker["name"]] = worker
    push(sup["worker_list"], worker)

# Set a global state variable
proc set_state(sup, key, value):
    sup["global_state"][key] = value

proc get_state(sup, key):
    if dict_has(sup["global_state"], key):
        return sup["global_state"][key]
    return nil

# Set the validation function for transition checks
proc set_validator(sup, fn):
    sup["validation_fn"] = fn

# ============================================================================
# Workflow definition
# ============================================================================

# Add a step to the workflow
proc add_step(sup, description, worker_name, input_fn, validate_fn):
    let step = {}
    step["id"] = len(sup["workflow"])
    step["description"] = description
    step["worker"] = worker_name
    step["input_fn"] = input_fn
    step["validate_fn"] = validate_fn
    step["status"] = "pending"
    step["result"] = nil
    step["attempts"] = 0
    step["errors"] = []
    push(sup["workflow"], step)
    return step["id"]

# ============================================================================
# Execution engine
# ============================================================================

# Run the entire workflow
proc run_workflow(sup):
    sup["status"] = "running"
    sup["current_step"] = 0
    let total = len(sup["workflow"])
    while sup["current_step"] < total and sup["status"] == "running":
        let step = sup["workflow"][sup["current_step"]]
        step["status"] = "running"
        # Get the worker
        if not dict_has(sup["workers"], step["worker"]):
            step["status"] = "failed"
            push(step["errors"], "Worker not found: " + step["worker"])
            sup["status"] = "failed"
            sup["stats"]["tasks_failed"] = sup["stats"]["tasks_failed"] + 1
            continue
        let worker = sup["workers"][step["worker"]]
        # Build input from state
        let task_input = step["description"]
        if step["input_fn"] != nil:
            task_input = step["input_fn"](sup["global_state"])
        # Execute with retries
        let success = false
        let attempts = 0
        while not success and attempts < sup["max_retries"]:
            attempts = attempts + 1
            step["attempts"] = attempts
            sup["stats"]["tasks_dispatched"] = sup["stats"]["tasks_dispatched"] + 1
            let outcome = worker_execute(worker, task_input, 1)
            if outcome["success"]:
                # Validate result
                let valid = true
                if step["validate_fn"] != nil:
                    valid = step["validate_fn"](outcome["result"], sup["global_state"])
                if valid:
                    step["result"] = outcome["result"]
                    step["status"] = "completed"
                    success = true
                    sup["stats"]["tasks_succeeded"] = sup["stats"]["tasks_succeeded"] + 1
                    # Update global state
                    set_state(sup, "step_" + str(step["id"]) + "_result", outcome["result"])
                    # Record in history
                    let entry = {}
                    entry["step"] = step["id"]
                    entry["worker"] = step["worker"]
                    entry["result"] = outcome["result"]
                    entry["attempts"] = attempts
                    push(sup["history"], entry)
                else:
                    push(step["errors"], "Validation failed on attempt " + str(attempts))
                    sup["stats"]["retries"] = sup["stats"]["retries"] + 1
            else:
                let err_msg = "Execution failed on attempt " + str(attempts)
                if len(outcome["errors"]) > 0:
                    err_msg = err_msg + ": " + outcome["errors"][0]
                push(step["errors"], err_msg)
                # Append error context for retry (self-healing)
                task_input = task_input + chr(10) + "Previous error: " + err_msg + chr(10) + "Please fix and retry."
                sup["stats"]["retries"] = sup["stats"]["retries"] + 1
        if not success:
            step["status"] = "failed"
            sup["stats"]["tasks_failed"] = sup["stats"]["tasks_failed"] + 1
            # Check if failure is fatal
            sup["status"] = "failed"
        sup["stats"]["total_steps"] = sup["stats"]["total_steps"] + 1
        sup["current_step"] = sup["current_step"] + 1
    if sup["status"] == "running":
        sup["status"] = "completed"
    return sup["status"]

# Dispatch a single task to a specific worker (ad-hoc)
proc dispatch(sup, worker_name, task):
    if not dict_has(sup["workers"], worker_name):
        return {"success": false, "error": "Worker not found"}
    let worker = sup["workers"][worker_name]
    sup["stats"]["tasks_dispatched"] = sup["stats"]["tasks_dispatched"] + 1
    let outcome = worker_execute(worker, task, sup["max_retries"])
    if outcome["success"]:
        sup["stats"]["tasks_succeeded"] = sup["stats"]["tasks_succeeded"] + 1
    else:
        sup["stats"]["tasks_failed"] = sup["stats"]["tasks_failed"] + 1
    return outcome

# ============================================================================
# Reporting
# ============================================================================

proc workflow_status(sup):
    let nl = chr(10)
    let out = "Supervisor: " + sup["name"] + " [" + sup["status"] + "]" + nl
    out = out + "Steps: " + str(len(sup["workflow"])) + ", Workers: " + str(len(sup["worker_list"])) + nl
    for i in range(len(sup["workflow"])):
        let step = sup["workflow"][i]
        let marker = "[ ]"
        if step["status"] == "running":
            marker = "[>]"
        if step["status"] == "completed":
            marker = "[x]"
        if step["status"] == "failed":
            marker = "[!]"
        out = out + "  " + marker + " " + str(i) + ". " + step["description"] + " (@" + step["worker"] + ")"
        if step["attempts"] > 1:
            out = out + " [" + str(step["attempts"]) + " attempts]"
        out = out + nl
    return out

proc stats_summary(sup):
    let s = sup["stats"]
    let nl = chr(10)
    return "Dispatched: " + str(s["tasks_dispatched"]) + nl + "Succeeded: " + str(s["tasks_succeeded"]) + nl + "Failed: " + str(s["tasks_failed"]) + nl + "Retries: " + str(s["retries"]) + nl + "Steps: " + str(s["total_steps"]) + nl
