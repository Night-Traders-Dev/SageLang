let d = {"x": 1, "y": 2}
d["z"] = 3
print d["x"] + d["z"]
print dict_has(d, "y")
dict_delete(d, "x")
print dict_has(d, "x")
print len(dict_keys(d))
print d["y"] + d["z"]
for k in d:
    print dict_has(d, k)
end
