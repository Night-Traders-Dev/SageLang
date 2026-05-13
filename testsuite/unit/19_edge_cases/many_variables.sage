# EXPECT: 190
# Test many variables in a single scope
var sum = 0
for i in range(20):
    var x = i
    sum = sum + x
print(sum)
