gc_disable()
# Verification Loop / Critic System
# Multi-pass validation: worker output -> critic evaluation -> accept or bounce back
# Supports rule-based validators, LLM-based critics, and composite checks

# ============================================================================
# Rule-based validators
# ============================================================================

# Create a validator that checks output against rules
proc create_validator():
    let v = {}
    v["rules"] = []
    v["checks_run"] = 0
    v["checks_passed"] = 0
    v["checks_failed"] = 0
    return v

# Add a validation rule (name + check function that returns {valid, message})
proc add_rule(validator, name, check_fn):
    let rule = {}
    rule["name"] = name
    rule["fn"] = check_fn
    push(validator["rules"], rule)

# Run all validation rules on an output
proc validate(validator, output, context):
    validator["checks_run"] = validator["checks_run"] + 1
    let results = []
    let all_passed = true
    for i in range(len(validator["rules"])):
        let rule = validator["rules"][i]
        let check = rule["fn"](output, context)
        let r = {}
        r["rule"] = rule["name"]
        r["passed"] = check["valid"]
        r["message"] = check["message"]
        push(results, r)
        if not check["valid"]:
            all_passed = false
    if all_passed:
        validator["checks_passed"] = validator["checks_passed"] + 1
    else:
        validator["checks_failed"] = validator["checks_failed"] + 1
    let result = {}
    result["valid"] = all_passed
    result["results"] = results
    result["error_summary"] = ""
    if not all_passed:
        let errors = ""
        for i in range(len(results)):
            if not results[i]["passed"]:
                if len(errors) > 0:
                    errors = errors + "; "
                errors = errors + results[i]["rule"] + ": " + results[i]["message"]
        result["error_summary"] = errors
    return result

# ============================================================================
# Common validation rules
# ============================================================================

# Check output is not empty
proc rule_not_empty(output, ctx):
    let r = {}
    if output == nil or (type(output) == "string" and len(output) == 0):
        r["valid"] = false
        r["message"] = "Output is empty"
    else:
        r["valid"] = true
        r["message"] = "OK"
    return r

# Check output length is within bounds
proc make_length_rule(min_len, max_len):
    proc check(output, ctx):
        let r = {}
        if type(output) != "string":
            r["valid"] = true
            r["message"] = "OK (non-string)"
            return r
        if len(output) < min_len:
            r["valid"] = false
            r["message"] = "Too short (" + str(len(output)) + " < " + str(min_len) + ")"
        if len(output) > max_len:
            r["valid"] = false
            r["message"] = "Too long (" + str(len(output)) + " > " + str(max_len) + ")"
        if len(output) >= min_len and len(output) <= max_len:
            r["valid"] = true
            r["message"] = "OK"
        return r
    return check

# Check output contains required keywords
proc make_contains_rule(keywords):
    proc check(output, ctx):
        let r = {}
        if type(output) != "string":
            r["valid"] = false
            r["message"] = "Not a string"
            return r
        let missing = []
        for i in range(len(keywords)):
            let found = false
            let kw = keywords[i]
            for j in range(len(output) - len(kw) + 1):
                if not found:
                    let is_match = true
                    for k in range(len(kw)):
                        if not is_match:
                            k = len(kw)
                        if is_match and output[j + k] != kw[k]:
                            is_match = false
                    if is_match:
                        found = true
            if not found:
                push(missing, kw)
        if len(missing) > 0:
            r["valid"] = false
            let msg = "Missing: "
            for i in range(len(missing)):
                if i > 0:
                    msg = msg + ", "
                msg = msg + missing[i]
            r["message"] = msg
        else:
            r["valid"] = true
            r["message"] = "OK"
        return r
    return check

# Check output does not contain forbidden patterns
proc make_forbidden_rule(patterns):
    proc check(output, ctx):
        let r = {}
        if type(output) != "string":
            r["valid"] = true
            r["message"] = "OK"
            return r
        for i in range(len(patterns)):
            let pat = patterns[i]
            for j in range(len(output) - len(pat) + 1):
                let is_match = true
                for k in range(len(pat)):
                    if not is_match:
                        k = len(pat)
                    if is_match and output[j + k] != pat[k]:
                        is_match = false
                if is_match:
                    r["valid"] = false
                    r["message"] = "Contains forbidden pattern: " + pat
                    return r
        r["valid"] = true
        r["message"] = "OK"
        return r
    return check

# ============================================================================
# LLM-based critic
# ============================================================================

# Create an LLM critic that evaluates output quality
proc create_critic(name, llm_fn, criteria):
    let c = {}
    c["name"] = name
    c["llm_fn"] = llm_fn
    c["criteria"] = criteria
    c["reviews"] = 0
    c["approvals"] = 0
    c["rejections"] = 0
    return c

# Have the critic review output
proc review(critic, task, output):
    critic["reviews"] = critic["reviews"] + 1
    let prompt = "Review this output for: " + critic["criteria"] + chr(10)
    prompt = prompt + "Task: " + task + chr(10)
    prompt = prompt + "Output: " + str(output) + chr(10)
    prompt = prompt + "Respond with APPROVE or REJECT followed by feedback."
    let response = critic["llm_fn"](prompt)
    let result = {}
    result["feedback"] = response
    # Parse approval/rejection
    let lower = ""
    for i in range(len(response)):
        let code = ord(response[i])
        if code >= 65 and code <= 90:
            lower = lower + chr(code + 32)
        else:
            lower = lower + response[i]
    let approved = false
    if len(lower) >= 7:
        if lower[0] == "a" and lower[1] == "p" and lower[2] == "p" and lower[3] == "r" and lower[4] == "o" and lower[5] == "v" and lower[6] == "e":
            approved = true
    result["approved"] = approved
    if approved:
        critic["approvals"] = critic["approvals"] + 1
    else:
        critic["rejections"] = critic["rejections"] + 1
    return result

# ============================================================================
# Verification loop
# ============================================================================

# Run a task through worker + critic loop until approved or max attempts
proc verify_loop(worker_fn, critic, task, max_attempts):
    let attempts = 0
    let feedback_history = []
    let current_task = task
    while attempts < max_attempts:
        attempts = attempts + 1
        # Worker produces output
        let output = worker_fn(current_task)
        # Critic reviews
        let result = review(critic, task, output)
        push(feedback_history, result)
        if result["approved"]:
            let outcome = {}
            outcome["output"] = output
            outcome["approved"] = true
            outcome["attempts"] = attempts
            outcome["feedback_history"] = feedback_history
            return outcome
        # Bounce back with feedback for self-correction
        current_task = task + chr(10) + "Previous attempt was rejected. Feedback: " + result["feedback"] + chr(10) + "Please fix and try again."
    let outcome = {}
    outcome["output"] = nil
    outcome["approved"] = false
    outcome["attempts"] = attempts
    outcome["feedback_history"] = feedback_history
    return outcome

# ============================================================================
# Composite validator (rules + optional critic)
# ============================================================================

proc create_composite(validator, critic):
    let comp = {}
    comp["validator"] = validator
    comp["critic"] = critic
    return comp

proc composite_check(comp, task, output, context):
    # First pass: rule-based validation (fast, deterministic)
    let rule_result = validate(comp["validator"], output, context)
    if not rule_result["valid"]:
        let r = {}
        r["valid"] = false
        r["stage"] = "rules"
        r["message"] = rule_result["error_summary"]
        return r
    # Second pass: LLM critic (slower, semantic)
    if comp["critic"] != nil:
        let critic_result = review(comp["critic"], task, output)
        if not critic_result["approved"]:
            let r = {}
            r["valid"] = false
            r["stage"] = "critic"
            r["message"] = critic_result["feedback"]
            return r
    let r = {}
    r["valid"] = true
    r["stage"] = "passed"
    r["message"] = "All checks passed"
    return r
