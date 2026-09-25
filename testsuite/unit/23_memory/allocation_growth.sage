# EXPECT: 200
# EXPECT: 398
# EXPECT: equal_within_bound
# EXPECT: unequal_beyond_bound
# EXPECT: PASS
#
# Allocation-growth bounds: a collection that grows to a few hundred entries by
# repeated push must work, and the growth accounting must stay consistent
# (bytes_allocated/bytes_freed are updated both under the GC mutex and, without
# it, from the growth path). Overlapping reallocs used to be able to request a
# wrapped-around size, which turns a large allocation into a tiny one.
let arr = []
var i = 0
while i < 200:
    push(arr, ["entry", i, i * 2])
    i = i + 1

print(len(arr))
print(arr[199][2])

# Recursive value equality is depth-bounded. Within the bound two deeply
# nested values compare equal; past it the comparison gives up and reports
# "unequal" rather than recursing off the C stack.
proc nest(depth, tag):
    var v = tag
    var d = 0
    while d < depth:
        v = [v]
        d = d + 1
    return v

# Keep the values behind variables so the interpreter cannot constant-fold.
let shallow_a = nest(100, "x")
let shallow_b = nest(100, "x")
if shallow_a == shallow_b:
    print("equal_within_bound")
else:
    print("FAIL: expected equal within depth bound")

# Past the bound the result is deliberately "not equal" — a safe answer.
# What matters is that it returns instead of overflowing the stack.
let deep_a = nest(400, "x")
let deep_b = nest(400, "x")
if deep_a == deep_b:
    print("FAIL: unexpectedly equal beyond depth bound")
else:
    print("unequal_beyond_bound")

print("PASS")
