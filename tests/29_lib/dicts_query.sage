# EXPECT: true
# EXPECT: true
# EXPECT: false
# EXPECT: [10, 20, nil]
# EXPECT: 1
# Test dicts module: has_all, has_any, select_values, count_missing
from dicts import has_all, has_any, select_values, count_missing

let d = {}
d["x"] = 10
d["y"] = 20

print has_all(d, ["x", "y"])
print has_any(d, ["x", "z"])
print has_any(d, ["a", "b"])
print select_values(d, ["x", "y", "z"], nil)
print count_missing(d, ["x", "y", "z"])
