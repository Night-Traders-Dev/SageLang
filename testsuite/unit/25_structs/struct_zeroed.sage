# Test that struct_new returns zeroed memory
# EXPECT: 0
# EXPECT: 0
# EXPECT: 0

let S = struct_def([["x", "int"], ["y", "int"], ["z", "double"]])
let s = struct_new(S)

print struct_get(s, S, "x")
print struct_get(s, S, "y")
print struct_get(s, S, "z")

mem_free(s)
