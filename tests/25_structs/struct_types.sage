# Test all supported field types
# EXPECT: 255
# EXPECT: 32000
# EXPECT: 100000
# EXPECT: 1e+07
# EXPECT: 2.5
# EXPECT: 3.14159

let S = struct_def([["a", "byte"], ["b", "short"], ["c", "int"], ["d", "long"], ["e", "float"], ["f", "double"]])

let s = struct_new(S)
struct_set(s, S, "a", 255)
struct_set(s, S, "b", 32000)
struct_set(s, S, "c", 100000)
struct_set(s, S, "d", 10000000)
struct_set(s, S, "e", 2.5)
struct_set(s, S, "f", 3.14159)

print struct_get(s, S, "a")
print struct_get(s, S, "b")
print struct_get(s, S, "c")
print struct_get(s, S, "d")
print struct_get(s, S, "e")
print struct_get(s, S, "f")

mem_free(s)
