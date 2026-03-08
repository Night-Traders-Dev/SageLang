# EXPECT: 3
# EXPECT: 4
# EXPECT: 4
# EXPECT: 3
let a = [1, 2, 3]
print(len(a))
push(a, 4)
print(len(a))
print(a[3])
pop(a)
print(len(a))
