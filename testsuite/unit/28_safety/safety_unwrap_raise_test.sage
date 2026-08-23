# EXPECT: unwrap_raises_ok
# EXPECT: unwrap_or_else_ok
# EXPECT: or_else_ok
# EXPECT: copy_deep_ok
# EXPECT: send_sync_ok
# EXPECT: PASS
# Tests for option.sage fixes and edge cases
import option

# --- unwrap() now raises instead of returning nil ---
let caught = false
try:
    option.unwrap(option.None())
catch e:
    if contains(e, "PANIC"):
        caught = true
if caught:
    print "unwrap_raises_ok"

# --- unwrap_or_else ---
proc default_77():
    return 77
let computed = option.unwrap_or_else(option.None(), default_77)
let direct = option.unwrap_or_else(option.Some(5), default_77)
if computed == 77 and direct == 5:
    print "unwrap_or_else_ok"

# --- or_else ---
proc fallback_99():
    return option.Some(99)
let fallback = option.or_else(option.None(), fallback_99)
let kept = option.or_else(option.Some(1), fallback_99)
if option.unwrap(fallback) == 99 and option.unwrap(kept) == 1:
    print "or_else_ok"

# --- deep copy ---
let orig = {"a": [1, 2, 3], "b": {"c": 42}}
let cp = option.copy(orig)
cp["a"][0] = 99
cp["b"]["c"] = 0
# Original must be unchanged
if orig["a"][0] == 1 and orig["b"]["c"] == 42:
    print "copy_deep_ok"

# --- Send/Sync on primitives and dicts ---
if option.is_send(0) and option.is_send("x") and option.is_send(true):
    if option.is_sync(0) == false:  # primitives are not Sync by default
        let d = {}
        d = option.mark_send(d)
        d = option.mark_sync(d)
        if option.is_send(d) and option.is_sync(d):
            print "send_sync_ok"

print "PASS"
