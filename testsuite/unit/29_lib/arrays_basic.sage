# EXPECT: [3, 2, 1]
# EXPECT: [1, 2, 3]
# EXPECT: [1, 2, 3, 4, 5, 6]
# EXPECT: [2, 4, 6]
# EXPECT: 6
# EXPECT: true
# EXPECT: false
# EXPECT: 2
# EXPECT: -1
# Test arrays module: copy, reverse, concat, map, reduce, contains, index_of
from arrays import copy, reverse, concat, map, reduce, contains, index_of

let a = [1, 2, 3]
print reverse(a)
let b = copy(a)
print b

print concat([1, 2, 3], [4, 5, 6])

proc double(x):
    return x * 2
print map(a, double)

proc add(acc, x):
    return acc + x
print reduce(a, 0, add)

print contains(a, 2)
print contains(a, 9)
print index_of(a, 3)
print index_of(a, 9)
