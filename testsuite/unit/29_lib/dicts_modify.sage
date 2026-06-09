# EXPECT: false
# EXPECT: 1
# Test dicts module: remove_keys, entries, keys, values
from dicts import remove_keys, size, keys, values

let d = {}
d["a"] = 1
d["b"] = 2
d["c"] = 3

remove_keys(d, ["a", "b"])
print dict_has(d, "a")
print size(d)
