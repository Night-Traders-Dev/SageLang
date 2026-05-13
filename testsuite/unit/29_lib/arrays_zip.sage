# EXPECT: [(1, a), (2, b), (3, c)]
# EXPECT: [1, 2, 3, 4, 5]
# Test arrays module: zip, append_all
from arrays import zip, append_all

print zip([1, 2, 3], ["a", "b", "c"])

let target = [1, 2, 3]
append_all(target, [4, 5])
print target
