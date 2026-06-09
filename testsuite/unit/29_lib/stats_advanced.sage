# EXPECT: [1, 3, 6, 10, 15]
# EXPECT: 2
# EXPECT: [0, 0.25, 0.5, 0.75, 1]
# Test stats module: cumulative, variance, normalize
from stats import cumulative, variance, normalize

print cumulative([1, 2, 3, 4, 5])
print variance([1, 2, 3, 4, 5])
print normalize([1, 2, 3, 4, 5])
