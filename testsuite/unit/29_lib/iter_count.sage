# EXPECT: [10, 15, 20, 25, 30]
# EXPECT: 42
# Test iter module: count, take, nth
from iter import count, take, nth

let c = count(10, 5)
print take(c, 5)

let c2 = count(0, 1)
print nth(c2, 42)
