# EXPECT: 0
# EXPECT: 1
# EXPECT: 2
# EXPECT: 1
# EXPECT: 3
# EXPECT: 5
var i = 0
while true:
    if i == 3:
        break
    print(i)
    i = i + 1
for x in [1, 2, 3, 4, 5]:
    if x % 2 == 0:
        continue
    print(x)
