gc_disable()
# Simple profiler for measuring function execution times
# Provides hierarchical timing, call counting, and flame graph data

# ============================================================================
# Profiler
# ============================================================================

proc create():
    let p = {}
    p["entries"] = {}
    p["stack"] = []
    p["enabled"] = true
    return p

# Start timing a section
proc begin(profiler, name):
    if not profiler["enabled"]:
        return
    let entry = {}
    entry["name"] = name
    entry["start"] = clock()
    push(profiler["stack"], entry)

# End timing a section
proc end_section(profiler, name):
    if not profiler["enabled"]:
        return
    let elapsed = 0
    if len(profiler["stack"]) > 0:
        let top = profiler["stack"][len(profiler["stack"]) - 1]
        elapsed = clock() - top["start"]
        pop(profiler["stack"])
    if not dict_has(profiler["entries"], name):
        let e = {}
        e["name"] = name
        e["total_time"] = 0
        e["call_count"] = 0
        e["min_time"] = elapsed
        e["max_time"] = elapsed
        profiler["entries"][name] = e
    let entry = profiler["entries"][name]
    entry["total_time"] = entry["total_time"] + elapsed
    entry["call_count"] = entry["call_count"] + 1
    if elapsed < entry["min_time"]:
        entry["min_time"] = elapsed
    if elapsed > entry["max_time"]:
        entry["max_time"] = elapsed

# Profile a function call
proc profile(profiler, name, fn):
    begin(profiler, name)
    let result = fn()
    end_section(profiler, name)
    return result

# ============================================================================
# Reporting
# ============================================================================

proc report(profiler):
    let nl = chr(10)
    let keys = dict_keys(profiler["entries"])
    let output = "=== Profiler Report ===" + nl
    for i in range(len(keys)):
        let e = profiler["entries"][keys[i]]
        let avg = 0
        if e["call_count"] > 0:
            avg = e["total_time"] / e["call_count"]
        output = output + e["name"] + ": "
        output = output + str(e["call_count"]) + " calls, "
        output = output + str(e["total_time"] * 1000) + "ms total, "
        output = output + str(avg * 1000) + "ms avg"
        output = output + nl
    output = output + "=====================" + nl
    return output

# Get sorted entries by total time (descending)
proc hotspots(profiler):
    let keys = dict_keys(profiler["entries"])
    let entries = []
    for i in range(len(keys)):
        push(entries, profiler["entries"][keys[i]])
    # Sort by total_time descending (insertion sort)
    let n = len(entries)
    for i in range(n):
        let j = i
        while j > 0 and entries[j - 1]["total_time"] < entries[j]["total_time"]:
            let temp = entries[j]
            entries[j] = entries[j - 1]
            entries[j - 1] = temp
            j = j - 1
    return entries

# Reset all profiling data
proc reset(profiler):
    profiler["entries"] = {}
    profiler["stack"] = []

# Enable/disable
proc enable(profiler):
    profiler["enabled"] = true

proc disable(profiler):
    profiler["enabled"] = false

# ============================================================================
# Simple benchmark runner
# ============================================================================

proc bench(name, fn, iterations):
    let start = clock()
    for i in range(iterations):
        fn()
    let total = clock() - start
    let per_iter = total / iterations
    let result = {}
    result["name"] = name
    result["iterations"] = iterations
    result["total_seconds"] = total
    result["per_iteration_ms"] = per_iter * 1000
    result["ops_per_second"] = iterations / total
    return result

proc bench_report(results):
    let nl = chr(10)
    let output = "=== Benchmark Results ===" + nl
    for i in range(len(results)):
        let r = results[i]
        output = output + r["name"] + ": "
        output = output + str(r["per_iteration_ms"]) + "ms/op, "
        output = output + str(r["ops_per_second"] | 0) + " ops/sec"
        output = output + nl
    return output
