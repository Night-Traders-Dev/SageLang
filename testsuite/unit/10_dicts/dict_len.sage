# EXPECT: 0
# EXPECT: 3
# EXPECT: 2
let empty = {}
print(len(empty))
let d = {"a": 1, "b": 2, "c": 3}
print(len(d))
dict_delete(d, "b")
print(len(d))
