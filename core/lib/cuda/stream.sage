# CUDA stream and event abstractions
# Provides stream management, event timing, and dependency graph construction

# Stream priority constants
let PRIORITY_DEFAULT = 0
let PRIORITY_HIGH = -1
let PRIORITY_LOW = 1

# ============================================================================
# Streams
# ============================================================================

# Create a stream descriptor
proc create_stream(priority):
    let s = {}
    s["id"] = 0
    s["priority"] = priority
    s["commands"] = []
    s["synchronized"] = true
    return s

# Create default stream
proc default_stream():
    return create_stream(0)

# Record a kernel launch on a stream
proc record_launch(stream, kernel_name, grid, block):
    let cmd = {}
    cmd["type"] = "kernel"
    cmd["name"] = kernel_name
    cmd["grid"] = grid
    cmd["block"] = block
    push(stream["commands"], cmd)
    stream["synchronized"] = false
    return cmd

# Record a memory copy on a stream
proc record_copy(stream, src, dst, size):
    let cmd = {}
    cmd["type"] = "memcpy"
    cmd["src"] = src
    cmd["dst"] = dst
    cmd["size"] = size
    push(stream["commands"], cmd)
    stream["synchronized"] = false
    return cmd

# Record a memset on a stream
proc record_memset(stream, dst, value, size):
    let cmd = {}
    cmd["type"] = "memset"
    cmd["dst"] = dst
    cmd["value"] = value
    cmd["size"] = size
    push(stream["commands"], cmd)
    stream["synchronized"] = false
    return cmd

# Synchronize a stream (mark all commands as complete)
proc synchronize(stream):
    stream["synchronized"] = true

# Get number of pending commands
proc pending_count(stream):
    if stream["synchronized"]:
        return 0
    return len(stream["commands"])

# ============================================================================
# Events
# ============================================================================

# Create an event
proc create_event():
    let e = {}
    e["recorded"] = false
    e["stream_id"] = -1
    e["command_index"] = -1
    e["elapsed_ms"] = 0
    return e

# Record an event on a stream
proc record_event(event, stream):
    event["recorded"] = true
    event["stream_id"] = stream["id"]
    event["command_index"] = len(stream["commands"])
    let cmd = {}
    cmd["type"] = "event"
    cmd["event"] = event
    push(stream["commands"], cmd)

# Calculate elapsed time between two events (in milliseconds)
proc elapsed_time(start_event, end_event):
    return end_event["elapsed_ms"] - start_event["elapsed_ms"]

# Make a stream wait for an event
proc stream_wait_event(stream, event):
    let cmd = {}
    cmd["type"] = "wait_event"
    cmd["event"] = event
    push(stream["commands"], cmd)

# ============================================================================
# Multi-stream execution plan
# ============================================================================

# Create an execution plan for overlapping compute and data transfer
proc create_plan():
    let plan = {}
    plan["streams"] = []
    plan["events"] = []
    plan["dependencies"] = []
    return plan

# Add a stream to the plan
proc add_stream(plan, name, priority):
    let s = create_stream(priority)
    s["id"] = len(plan["streams"])
    s["name"] = name
    push(plan["streams"], s)
    return s

# Add a dependency: stream B waits for stream A's event
proc add_dependency(plan, event, wait_stream):
    let dep = {}
    dep["event"] = event
    dep["stream"] = wait_stream
    push(plan["dependencies"], dep)

# Get plan statistics
proc plan_stats(plan):
    let stats = {}
    stats["num_streams"] = len(plan["streams"])
    stats["num_events"] = len(plan["events"])
    stats["num_dependencies"] = len(plan["dependencies"])
    let total_commands = 0
    let kernel_count = 0
    let copy_count = 0
    for i in range(len(plan["streams"])):
        let cmds = plan["streams"][i]["commands"]
        total_commands = total_commands + len(cmds)
        for j in range(len(cmds)):
            if cmds[j]["type"] == "kernel":
                kernel_count = kernel_count + 1
            if cmds[j]["type"] == "memcpy":
                copy_count = copy_count + 1
    stats["total_commands"] = total_commands
    stats["kernel_launches"] = kernel_count
    stats["memory_copies"] = copy_count
    return stats

# ============================================================================
# Pipeline pattern helpers
# ============================================================================

# Create a double-buffered pipeline (overlap compute with transfer)
proc double_buffer_plan(num_iterations):
    let plan = create_plan()
    let compute_stream = add_stream(plan, "compute", 0)
    let transfer_stream = add_stream(plan, "transfer", 0)
    for i in range(num_iterations):
        # Transfer next batch while computing current
        let transfer_done = create_event()
        record_copy(transfer_stream, "host", "device_" + str(i), 0)
        record_event(transfer_done, transfer_stream)
        push(plan["events"], transfer_done)
        # Compute waits for transfer
        stream_wait_event(compute_stream, transfer_done)
        record_launch(compute_stream, "process_batch_" + str(i), [1, 1, 1], [256, 1, 1])
    return plan

# Format stream command log
proc format_stream(stream):
    let result = "Stream " + str(stream["id"])
    if dict_has(stream, "name"):
        result = result + " (" + stream["name"] + ")"
    result = result + ": " + str(len(stream["commands"])) + " commands"
    return result
