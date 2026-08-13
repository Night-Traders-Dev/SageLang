# C-backend regression: and/or must short-circuit (right operand evaluated
# only when the left operand does not decide the result).
# Previously the C backend emitted eager sage_and()/sage_or() calls, so a
# guard like  best == nil or best["priority"] > 0  dereferenced a nil
# value at runtime, while the interpreter short-circuits correctly.

let side_effect_count = 0

proc bump():
    side_effect_count = side_effect_count + 1
    return true

# --- OR: right operand must not run when left is true ----------------
let r1 = true or bump()
print "or_skips=" + str(side_effect_count)

let r2 = false or bump()
print "or_runs=" + str(side_effect_count)

# --- AND: right operand must not run when left is false --------------
let r3 = false and bump()
print "and_skips=" + str(side_effect_count)

let r4 = true and bump()
print "and_runs=" + str(side_effect_count)

# --- nil-guard idiom: previously a runtime crash ----------------------
let best = nil
let ok = best == nil or best["priority"] > 0
print "nil_guard_or=" + str(ok)

let worst = nil
let ok2 = worst != nil and worst["priority"] > 0
print "nil_guard_and=" + str(ok2)

# --- value semantics match the interpreter (boolean result) -----------
print "or_value=" + str(0 or 5)
print "and_value=" + str(1 and 7)

# --- mixed with loops/conditions ---------------------------------------
let count = 0
while count < 5 and count >= 0:
    count = count + 1
print "loop=" + str(count)

let flag = false
if count == 5 or flag:
    print "cond=true"
else:
    print "cond=false"