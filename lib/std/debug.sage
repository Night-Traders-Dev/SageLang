gc_disable()
# Debugging utilities
# Stack traces, value inspection, assertions, breakpoints, watch expressions

# ============================================================================
# Value inspection
# ============================================================================

proc type_name(val):
    return type(val)

proc inspect(val):
    let t = type(val)
    let result = "<" + t + ">"
    if t == "number":
        result = result + " " + str(val)
    if t == "string":
        result = result + " " + chr(34) + val + chr(34) + " (len=" + str(len(val)) + ")"
    if t == "bool":
        if val:
            result = result + " true"
        else:
            result = result + " false"
    if t == "nil":
        result = result + " nil"
    if t == "array":
        result = result + " [" + str(len(val)) + " elements]"
    if t == "dict":
        result = result + " {" + str(len(dict_keys(val))) + " keys}"
    return result

proc dump(label, val):
    print "[DEBUG] " + label + " = " + inspect(val)

# ============================================================================
# Trace / logging
# ============================================================================

let _trace_enabled = false
let _trace_depth = 0

proc trace_enable():
    _trace_enabled = true

proc trace_disable():
    _trace_enabled = false

proc trace(message):
    if _trace_enabled:
        let indent = ""
        for i in range(_trace_depth):
            indent = indent + "  "
        print "[TRACE] " + indent + message

proc trace_enter(fn_name):
    if _trace_enabled:
        trace("-> " + fn_name)
        _trace_depth = _trace_depth + 1

proc trace_exit(fn_name):
    if _trace_enabled:
        _trace_depth = _trace_depth - 1
        trace("<- " + fn_name)

# ============================================================================
# Assertions with diagnostics
# ============================================================================

proc assert_msg(condition, message):
    if not condition:
        print "[ASSERT FAILED] " + message
        raise "Assertion failed: " + message

proc unreachable(message):
    raise "Unreachable code reached: " + message

proc todo(message):
    raise "TODO: " + message

proc deprecated(message):
    print "[DEPRECATED] " + message

# ============================================================================
# Watch expressions
# ============================================================================

proc create_watcher():
    let w = {}
    w["watches"] = {}
    w["history"] = {}
    return w

proc watch(watcher, name, value):
    let old = nil
    if dict_has(watcher["watches"], name):
        old = watcher["watches"][name]
    watcher["watches"][name] = value
    if not dict_has(watcher["history"], name):
        watcher["history"][name] = []
    push(watcher["history"][name], value)
    if old != nil and old != value:
        print "[WATCH] " + name + " changed: " + str(old) + " -> " + str(value)

proc get_watch(watcher, name):
    if dict_has(watcher["watches"], name):
        return watcher["watches"][name]
    return nil

proc watch_history(watcher, name):
    if dict_has(watcher["history"], name):
        return watcher["history"][name]
    return []

# ============================================================================
# Timer / profiling helpers
# ============================================================================

proc time_it(label, fn):
    let start = clock()
    let result = fn()
    let elapsed = clock() - start
    print "[TIME] " + label + ": " + str(elapsed * 1000) + "ms"
    return result

# ============================================================================
# Memory snapshot
# ============================================================================

proc memory_snapshot():
    let stats = gc_stats()
    let snap = {}
    snap["objects"] = stats["num_objects"]
    snap["bytes"] = stats["current_bytes"]
    snap["collections"] = stats["collections"]
    return snap

proc memory_diff(before, after):
    let diff = {}
    diff["objects"] = after["objects"] - before["objects"]
    diff["bytes"] = after["bytes"] - before["bytes"]
    diff["collections"] = after["collections"] - before["collections"]
    return diff
