# EXPECT: 2
# EXPECT: 2
# EXPECT: 3
let a = [1, 2, 3, 4, 5]
let s = slice(a, 1, 3)
print(len(s))
print(s[0])
print(s[1])
