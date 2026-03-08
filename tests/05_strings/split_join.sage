# EXPECT: 3
# EXPECT: a
# EXPECT: b
# EXPECT: c
# EXPECT: a-b-c
let parts = split("a,b,c", ",")
print(len(parts))
print(parts[0])
print(parts[1])
print(parts[2])
print(join(parts, "-"))
