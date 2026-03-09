# Test string builtins in C backend
print upper("hello")
print lower("WORLD")
print strip("  hi  ")

# split and join
let parts = split("a,b,c", ",")
print len(parts)
print parts[0]
print parts[2]

let joined = join(parts, "-")
print joined

# replace
print replace("hello world", "world", "sage")
