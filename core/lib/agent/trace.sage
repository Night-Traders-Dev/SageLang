gc_disable()
# SFT Trace Collection for Agent Training
# Records perfect agent execution traces (state, prompt, tool calls, output)
# for Supervised Fine-Tuning (SFT) and LoRA training data generation

# ============================================================================
# Trace recording
# ============================================================================

proc create_recorder():
    let rec = {}
    rec["traces"] = []
    rec["current_trace"] = nil
    rec["total_steps"] = 0
    return rec

# Start recording a new trace
proc begin_trace(rec, task):
    let trace = {}
    trace["task"] = task
    trace["steps"] = []
    trace["start_time"] = clock()
    trace["end_time"] = 0
    trace["success"] = false
    trace["total_tokens"] = 0
    rec["current_trace"] = trace
    return trace

# Record a step in the current trace
proc record_step(rec, step_type, input_text, output_text, tool_name, tool_args, tool_result):
    if rec["current_trace"] == nil:
        return
    let step = {}
    step["type"] = step_type
    step["input"] = input_text
    step["output"] = output_text
    step["tool_name"] = tool_name
    step["tool_args"] = tool_args
    step["tool_result"] = tool_result
    step["timestamp"] = clock()
    push(rec["current_trace"]["steps"], step)
    rec["total_steps"] = rec["total_steps"] + 1

# Record a thinking step
proc record_thought(rec, thought):
    record_step(rec, "thought", thought, "", "", "", "")

# Record a tool call
proc record_tool_call(rec, tool_name, args, result):
    record_step(rec, "tool_call", "", "", tool_name, str(args), str(result))

# Record the final output
proc record_output(rec, output):
    record_step(rec, "output", "", output, "", "", "")

# End the current trace
proc end_trace(rec, success):
    if rec["current_trace"] == nil:
        return
    rec["current_trace"]["end_time"] = clock()
    rec["current_trace"]["success"] = success
    push(rec["traces"], rec["current_trace"])
    rec["current_trace"] = nil

# ============================================================================
# Training data generation
# ============================================================================

# Convert traces to SFT training examples (prompt -> completion pairs)
proc to_sft_examples(rec):
    let examples = []
    for i in range(len(rec["traces"])):
        let trace = rec["traces"][i]
        if not trace["success"]:
            continue
        # Build prompt from task
        let prompt = "Task: " + trace["task"] + chr(10)
        # Build completion from steps
        let completion = ""
        for j in range(len(trace["steps"])):
            let step = trace["steps"][j]
            if step["type"] == "thought":
                completion = completion + "Thought: " + step["input"] + chr(10)
            if step["type"] == "tool_call":
                completion = completion + "Action: " + step["tool_name"] + "(" + step["tool_args"] + ")" + chr(10)
                completion = completion + "Result: " + step["tool_result"] + chr(10)
            if step["type"] == "output":
                completion = completion + "Answer: " + step["output"] + chr(10)
        let example = {}
        example["prompt"] = prompt
        example["completion"] = completion
        example["task"] = trace["task"]
        push(examples, example)
    return examples

# Convert traces to chat-format training data
proc to_chat_examples(rec):
    let examples = []
    for i in range(len(rec["traces"])):
        let trace = rec["traces"][i]
        if not trace["success"]:
            continue
        let messages = []
        let user_msg = {}
        user_msg["role"] = "user"
        user_msg["content"] = trace["task"]
        push(messages, user_msg)
        let assistant_content = ""
        for j in range(len(trace["steps"])):
            let step = trace["steps"][j]
            if step["type"] == "thought":
                assistant_content = assistant_content + "Thought: " + step["input"] + chr(10)
            if step["type"] == "tool_call":
                assistant_content = assistant_content + "TOOL: " + step["tool_name"] + "(" + step["tool_args"] + ")" + chr(10)
            if step["type"] == "output":
                assistant_content = assistant_content + step["output"]
        let asst_msg = {}
        asst_msg["role"] = "assistant"
        asst_msg["content"] = assistant_content
        push(messages, asst_msg)
        let example = {}
        example["messages"] = messages
        push(examples, example)
    return examples

# Convert to DPO preference pairs (successful traces = chosen, failed = rejected)
proc to_preference_pairs(rec):
    let pairs = []
    let successful = []
    let failed = []
    for i in range(len(rec["traces"])):
        if rec["traces"][i]["success"]:
            push(successful, rec["traces"][i])
        else:
            push(failed, rec["traces"][i])
    # Pair successful with failed traces for the same task type
    for i in range(len(successful)):
        for j in range(len(failed)):
            let pair = {}
            pair["prompt"] = successful[i]["task"]
            pair["chosen"] = ""
            for k in range(len(successful[i]["steps"])):
                let step = successful[i]["steps"][k]
                if step["type"] == "output":
                    pair["chosen"] = step["output"]
            pair["rejected"] = ""
            for k in range(len(failed[j]["steps"])):
                let step = failed[j]["steps"][k]
                if step["type"] == "output":
                    pair["rejected"] = step["output"]
            if len(pair["chosen"]) > 0 and len(pair["rejected"]) > 0:
                push(pairs, pair)
    return pairs

# ============================================================================
# Export
# ============================================================================

# Export traces as text for inspection
proc export_text(rec):
    let nl = chr(10)
    let out = "=== Agent Traces ===" + nl
    out = out + "Total traces: " + str(len(rec["traces"])) + nl
    out = out + "Total steps: " + str(rec["total_steps"]) + nl + nl
    for i in range(len(rec["traces"])):
        let trace = rec["traces"][i]
        out = out + "--- Trace " + str(i + 1) + " ---" + nl
        out = out + "Task: " + trace["task"] + nl
        out = out + "Success: " + str(trace["success"]) + nl
        out = out + "Steps: " + str(len(trace["steps"])) + nl
        for j in range(len(trace["steps"])):
            let step = trace["steps"][j]
            out = out + "  [" + step["type"] + "] "
            if step["type"] == "thought":
                out = out + step["input"]
            if step["type"] == "tool_call":
                out = out + step["tool_name"] + "(" + step["tool_args"] + ") -> " + step["tool_result"]
            if step["type"] == "output":
                out = out + step["output"]
            out = out + nl
        out = out + nl
    return out

# Stats
proc stats(rec):
    let s = {}
    s["total_traces"] = len(rec["traces"])
    s["total_steps"] = rec["total_steps"]
    let success_count = 0
    for i in range(len(rec["traces"])):
        if rec["traces"][i]["success"]:
            success_count = success_count + 1
    s["successful"] = success_count
    s["failed"] = len(rec["traces"]) - success_count
    s["success_rate"] = 0
    if len(rec["traces"]) > 0:
        s["success_rate"] = success_count / len(rec["traces"])
    return s
