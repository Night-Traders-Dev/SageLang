# RUN: run
# EXPECT: tracing
# EXPECT: orc
# EXPECT: 3
# EXPECT: hello
# EXPECT: 42
# EXPECT: reassigned
# EXPECT: done
# Test ORC (Optimized Reference Counting) mode - trial deletion cycle collector

# Default mode is tracing
print gc_mode()

# Switch to ORC mode
gc_set_orc()
print gc_mode()

# Basic operations work in ORC mode
let arr = [1, 2, 3]
print len(arr)

let s = "hello"
print s

let d = {}
d["x"] = 42
print d["x"]

# Variable reassignment (tests arc_assign_value path in ORC mode)
let a = "first"
a = "second"
a = "reassigned"
print a

# Nested structures (potential cycle candidates)
let nested = [[1, 2], [3, 4]]
let flat = []
for sub in nested:
    for item in sub:
        push(flat, item)

# Force cycle collection to exercise ORC trial deletion
gc_collect()

# Class instances (complex object graphs for ORC)
class Node:
    proc init(self, val):
        self.val = val
        self.next = nil

let n1 = Node(10)
let n2 = Node(20)
n1.next = n2

# Overwrite references to trigger ORC candidate marking
n1 = nil
n2 = nil

# Stress: allocate and discard objects to trigger ORC cycle collection
for i in range(200):
    let tmp = [i, i + 1, i + 2]
    let tmp2 = {"key": tmp}

print "done"
