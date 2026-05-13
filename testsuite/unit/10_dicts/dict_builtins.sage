# EXPECT: true
# EXPECT: false
# EXPECT: true
let d = {"name": "Alice", "age": 30}
print(dict_has(d, "name"))
print(dict_has(d, "missing"))
dict_delete(d, "age")
print(not dict_has(d, "age"))
