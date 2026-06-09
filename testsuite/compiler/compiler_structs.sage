# Test struct builtins in C backend
let Point = struct_def([["x", "int"], ["y", "int"], ["z", "double"]])
print struct_size(Point)

let p = struct_new(Point)
struct_set(p, Point, "x", 10)
struct_set(p, Point, "y", 20)
struct_set(p, Point, "z", 3.14)

print struct_get(p, Point, "x")
print struct_get(p, Point, "y")
print struct_get(p, Point, "z")

mem_free(p)
