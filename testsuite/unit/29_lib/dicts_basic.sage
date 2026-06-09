# EXPECT: true
# EXPECT: false
# EXPECT: 2
# EXPECT: 42
# EXPECT: default
# Test dicts module: has, size, get_or
from dicts import has, size, get_or

let d = {}
d["a"] = 42
d["b"] = 99

print has(d, "a")
print has(d, "c")
print size(d)
print get_or(d, "a", 0)
print get_or(d, "z", "default")
