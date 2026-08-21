let d = {"x": 1, "y": 2}
d["z"] = 3
print d["x"] + d["z"]
print dict_has(d, "y")
print dict_keys(d)
print dict_values(d)
dict_delete(d, "x")
print d
for k in d:
    print k
end
