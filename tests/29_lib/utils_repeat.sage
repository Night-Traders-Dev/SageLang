# EXPECT: [0, 0, 0, 0, 0]
# EXPECT: (2, 1)
# EXPECT: nil
# EXPECT: nil
# Test utils module: repeat_value, swap, head/last on empty
from utils import repeat_value, swap, head, last

print repeat_value(0, 5)
print swap(1, 2)
print head([])
print last([])
