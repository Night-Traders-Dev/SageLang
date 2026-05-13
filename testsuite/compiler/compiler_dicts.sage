# Test dictionaries in C backend
let d = {"name": "Alice", "age": 30}
print d["name"]
print d["age"]

# dict_keys and dict_values
let keys = dict_keys(d)
print len(keys)

# dict_has
print dict_has(d, "name")
print dict_has(d, "missing")

# dict_delete
dict_delete(d, "age")
print len(d)
