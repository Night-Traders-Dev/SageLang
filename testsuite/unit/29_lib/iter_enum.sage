# EXPECT: (0, a)
# EXPECT: (1, b)
# EXPECT: (2, c)
# Test iter module: enumerate_array
from iter import enumerate_array

let e = enumerate_array(["a", "b", "c"])
print next(e)
print next(e)
print next(e)
