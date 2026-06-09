gc_disable()
# EXPECT: true
# EXPECT: false
# EXPECT: 3
# EXPECT: true

import std.trait

# Define a trait
let Printable = trait.define("Printable", ["to_string"])

# Test implements
let obj1 = {"to_string": "yes"}
let obj2 = {"name": "test"}
print trait.implements(obj1, Printable)
print trait.implements(obj2, Printable)

# Filter/map utilities
let nums = [1, 2, 3, 4, 5]

proc is_odd(x):
    return (x & 1) != 0

let odds = trait.trait_filter(nums, is_odd)
print len(odds)

print trait.any(nums, is_odd)
