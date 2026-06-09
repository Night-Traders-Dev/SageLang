# EXPECT: [0, 2, 4, 6, 8]
# EXPECT: [5, 4, 3, 2, 1]
# EXPECT: [hi, hi, hi]
# Test iter module: range_step, repeat, take
from iter import range_step, repeat, take

let r = range_step(0, 10, 2)
print take(r, 5)

let down = range_step(5, 0, 0 - 1)
print take(down, 5)

let rep = repeat("hi", 3)
print take(rep, 3)
