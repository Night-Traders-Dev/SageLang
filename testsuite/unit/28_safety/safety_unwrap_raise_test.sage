# EXPECT: unwrap_raises_ok
# EXPECT: unwrap_or_else_ok
# EXPECT: or_else_ok
# EXPECT: copy_deep_ok
# EXPECT: send_sync_ok
# EXPECT: PASS
# Tests for safety.sage fixes and edge cases
import safety

# --- unwrap() now raises instead of returning nil ---
let caught = false
try:
    safety.unwrap(safety.None())
catch e:
    if contains(e, "PANIC"):
        caught = true
    end
end
if caught:
    print "unwrap_raises_ok"
end

# --- unwrap_or_else ---
proc default_77():
    return 77
end
let computed = safety.unwrap_or_else(safety.None(), default_77)
let direct = safety.unwrap_or_else(safety.Some(5), default_77)
if computed == 77 and direct == 5:
    print "unwrap_or_else_ok"
end

# --- or_else ---
proc fallback_99():
    return safety.Some(99)
end
let fallback = safety.or_else(safety.None(), fallback_99)
let kept = safety.or_else(safety.Some(1), fallback_99)
if safety.unwrap(fallback) == 99 and safety.unwrap(kept) == 1:
    print "or_else_ok"
end

# --- deep copy ---
let orig = {"a": [1, 2, 3], "b": {"c": 42}}
let cp = safety.copy(orig)
cp["a"][0] = 99
cp["b"]["c"] = 0
# Original must be unchanged
if orig["a"][0] == 1 and orig["b"]["c"] == 42:
    print "copy_deep_ok"
end

# --- Send/Sync on primitives and dicts ---
if safety.is_send(0) and safety.is_send("x") and safety.is_send(true):
    if safety.is_sync(0) == false:  # primitives are not Sync by default
        let d = {}
        d = safety.mark_send(d)
        d = safety.mark_sync(d)
        if safety.is_send(d) and safety.is_sync(d):
            print "send_sync_ok"
        end
    end
end

print "PASS"
