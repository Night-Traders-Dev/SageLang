# EXPECT: true
# Test assert module: assert_array_contains
from assert import assert_array_contains

print assert_array_contains([1, 2, 3], 2, "should contain 2")
