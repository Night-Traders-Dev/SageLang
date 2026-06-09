# EXPECT: 42
# EXPECT: hello
# EXPECT: fallback
# EXPECT: true
# EXPECT: false
# EXPECT: true
# EXPECT: false
# EXPECT: 1
# EXPECT: 3
# Test utils module: identity, choose, default_if_nil, is_even, is_odd, between, head, last
from utils import identity, choose, default_if_nil, is_even, is_odd, between, head, last

print identity(42)
print choose(true, "hello", "bye")
print default_if_nil(nil, "fallback")
print is_even(4)
print is_even(3)
print between(5, 1, 10)
print between(15, 1, 10)
print head([1, 2, 3])
print last([1, 2, 3])
