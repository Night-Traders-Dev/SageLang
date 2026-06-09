gc_disable()
# EXPECT: true
# EXPECT: Red
# EXPECT: 42
# EXPECT: true
# EXPECT: default
# EXPECT: true
# EXPECT: true

import std.enum

# Basic enum
let Color = enum.enum_def("Color", ["Red", "Green", "Blue"])
let red = enum.variant(Color, "Red")
print enum.is_variant(red, "Red")
print enum.variant_name(red)

# Result type
let success = enum.ok(42)
print enum.unwrap(success)
print enum.is_ok(success)

let failure = enum.err("oops")
print enum.unwrap_or(failure, "default")
print enum.is_err(failure)

# Option type
let val = enum.some(10)
print enum.is_some(val)
