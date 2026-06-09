# EXPECT: [1, 2, 3, 1, 2, 3, 1]
# Test iter module: cycle, take
from iter import cycle, take

let c = cycle([1, 2, 3])
print take(c, 7)
