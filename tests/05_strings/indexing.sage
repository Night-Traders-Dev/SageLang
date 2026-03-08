# EXPECT: 5
# EXPECT: hel
# String length and slicing
let s = "hello"
print(len(s))
let parts = split(s, "")
let sub = slice(parts, 0, 3)
print(join(sub, ""))
