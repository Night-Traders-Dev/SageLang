# EXPECT: 15
# EXPECT: 120
# EXPECT: 1
# EXPECT: 5
# EXPECT: 3
# EXPECT: 4
# Test stats module: sum, product, min_value, max_value, mean, range_span
from stats import sum, product, min_value, max_value, mean, range_span

print sum([1, 2, 3, 4, 5])
print product([1, 2, 3, 4, 5])
print min_value([3, 1, 4, 1, 5])
print max_value([3, 1, 4, 1, 5])
print mean([1, 2, 3, 4, 5])
print range_span([3, 1, 4, 1, 5])
