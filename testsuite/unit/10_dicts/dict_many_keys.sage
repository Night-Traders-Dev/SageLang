# EXPECT: 3
# EXPECT: true
# EXPECT: true
# EXPECT: true
# Test dict with many keys (hash table)
let d = {"a": 1, "b": 2, "c": 3, "d": 4, "e": 5, "f": 6, "g": 7, "h": 8}
print(d["c"])
print(dict_has(d, "a"))
print(dict_has(d, "h"))
print(dict_has(d, "e"))
