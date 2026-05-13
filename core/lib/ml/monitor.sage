gc_disable()
# Training monitor - Live progress tracking, memory usage, performance metrics

# ============================================================================
# Training monitor
# ============================================================================

proc create():
    let mon = {}
    mon["start_time"] = clock()
    mon["step"] = 0
    mon["losses"] = []
    mon["lrs"] = []
    mon["grad_norms"] = []
    mon["step_times"] = []
    mon["memory_snapshots"] = []
    mon["checkpoints"] = []
    mon["best_loss"] = 999999
    mon["best_step"] = 0
    mon["total_tokens"] = 0
    mon["warnings"] = []
    return mon

# Record a training step
proc log_step(mon, loss, lr, grad_norm, tokens):
    mon["step"] = mon["step"] + 1
    push(mon["losses"], loss)
    push(mon["lrs"], lr)
    push(mon["grad_norms"], grad_norm)
    let step_time = 0
    if mon["step"] > 1:
        let prev_time = mon["start_time"]
        if len(mon["step_times"]) > 0:
            prev_time = mon["step_times"][len(mon["step_times"]) - 1]
    push(mon["step_times"], clock())
    mon["total_tokens"] = mon["total_tokens"] + tokens
    if loss < mon["best_loss"]:
        mon["best_loss"] = loss
        mon["best_step"] = mon["step"]
    # Auto-detect issues
    if loss != loss:
        push(mon["warnings"], "Step " + str(mon["step"]) + ": NaN loss detected")
    if loss > 100:
        push(mon["warnings"], "Step " + str(mon["step"]) + ": Very high loss (" + str(loss) + ")")
    if grad_norm > 10:
        push(mon["warnings"], "Step " + str(mon["step"]) + ": Large gradient norm (" + str(grad_norm) + ")")

# Take a memory snapshot
proc snapshot_memory(mon):
    let stats = gc_stats()
    let snap = {}
    snap["step"] = mon["step"]
    snap["objects"] = stats["num_objects"]
    snap["bytes"] = stats["current_bytes"]
    snap["collections"] = stats["collections"]
    snap["time"] = clock()
    push(mon["memory_snapshots"], snap)
    return snap

# Save a checkpoint marker
proc checkpoint(mon, path):
    let cp = {}
    cp["step"] = mon["step"]
    cp["loss"] = mon["losses"][len(mon["losses"]) - 1]
    cp["path"] = path
    cp["time"] = clock()
    push(mon["checkpoints"], cp)

# ============================================================================
# Progress display
# ============================================================================

proc progress_bar(current, total, width):
    let filled = (current * width / total) | 0
    let bar = "["
    for i in range(width):
        if i < filled:
            bar = bar + "="
        if i == filled:
            bar = bar + ">"
        if i > filled:
            bar = bar + " "
    bar = bar + "] " + str(current) + "/" + str(total)
    return bar

proc format_time(seconds):
    if seconds < 60:
        return str((seconds * 10) | 0) + "s"
    if seconds < 3600:
        let mins = (seconds / 60) | 0
        let secs = seconds - mins * 60
        return str(mins) + "m" + str(secs | 0) + "s"
    let hrs = (seconds / 3600) | 0
    let mins = ((seconds - hrs * 3600) / 60) | 0
    return str(hrs) + "h" + str(mins) + "m"

proc print_progress(mon, total_steps):
    let step = mon["step"]
    let loss = 0
    if len(mon["losses"]) > 0:
        loss = mon["losses"][len(mon["losses"]) - 1]
    let elapsed = clock() - mon["start_time"]
    let eta = 0
    if step > 0:
        eta = elapsed * (total_steps - step) / step
    let tokens_per_sec = 0
    if elapsed > 0:
        tokens_per_sec = (mon["total_tokens"] / elapsed) | 0
    let bar = progress_bar(step, total_steps, 30)
    print bar + " loss=" + str(loss) + " best=" + str(mon["best_loss"]) + " eta=" + format_time(eta) + " tok/s=" + str(tokens_per_sec)

# ============================================================================
# Summary report
# ============================================================================

proc summary(mon):
    let nl = chr(10)
    let elapsed = clock() - mon["start_time"]
    let out = "=== Training Monitor Report ===" + nl
    out = out + "Steps completed: " + str(mon["step"]) + nl
    out = out + "Total time: " + format_time(elapsed) + nl
    out = out + "Total tokens: " + str(mon["total_tokens"]) + nl
    if elapsed > 0:
        out = out + "Throughput: " + str((mon["total_tokens"] / elapsed) | 0) + " tokens/sec" + nl
    if mon["step"] > 0:
        out = out + "Avg time/step: " + str((elapsed / mon["step"] * 1000) | 0) + " ms" + nl
    out = out + "Best loss: " + str(mon["best_loss"]) + " (step " + str(mon["best_step"]) + ")" + nl
    if len(mon["losses"]) > 0:
        out = out + "Final loss: " + str(mon["losses"][len(mon["losses"]) - 1]) + nl
        # Loss trend
        let first = mon["losses"][0]
        let last = mon["losses"][len(mon["losses"]) - 1]
        let improvement = ((first - last) / first * 100) | 0
        out = out + "Loss improvement: " + str(improvement) + "%" + nl
    if len(mon["warnings"]) > 0:
        out = out + nl + "Warnings:" + nl
        for i in range(len(mon["warnings"])):
            out = out + "  - " + mon["warnings"][i] + nl
    if len(mon["checkpoints"]) > 0:
        out = out + nl + "Checkpoints:" + nl
        for i in range(len(mon["checkpoints"])):
            let cp = mon["checkpoints"][i]
            out = out + "  Step " + str(cp["step"]) + ": loss=" + str(cp["loss"]) + " -> " + cp["path"] + nl
    if len(mon["memory_snapshots"]) > 0:
        let last_snap = mon["memory_snapshots"][len(mon["memory_snapshots"]) - 1]
        out = out + nl + "Memory:" + nl
        out = out + "  Objects: " + str(last_snap["objects"]) + nl
        out = out + "  Bytes: " + str(last_snap["bytes"]) + nl
        out = out + "  GC collections: " + str(last_snap["collections"]) + nl
    out = out + "===============================" + nl
    return out

# ============================================================================
# Export data for visualization
# ============================================================================

proc export_losses(mon):
    return mon["losses"]

proc export_lrs(mon):
    return mon["lrs"]

proc export_grad_norms(mon):
    return mon["grad_norms"]
