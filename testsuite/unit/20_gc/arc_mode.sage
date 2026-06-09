# RUN: run
# EXPECT: tracing
# EXPECT: arc
# EXPECT: 3
# EXPECT: hello
# EXPECT: 42
# EXPECT: done
# Test ARC (Automatic Reference Counting) mode

# Default mode is tracing
print gc_mode()

# Switch to ARC mode
gc_set_arc()
print gc_mode()

# Basic operations work in ARC mode
let arr = [1, 2, 3]
print len(arr)

let s = "hello"
print s

let d = {}
d["x"] = 42
print d["x"]

# Variable reassignment (tests arc_assign_value path)
let a = "first"
a = "second"
a = "third"

# Nested structures
let nested = [[1, 2], [3, 4]]
let flat = []
for sub in nested:
    for item in sub:
        push(flat, item)

print "done"
