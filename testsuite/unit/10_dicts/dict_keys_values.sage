# EXPECT: 2
# EXPECT: 2
let d = {"x": 10, "y": 20}
let k = dict_keys(d)
let v = dict_values(d)
print(len(k))
print(len(v))
