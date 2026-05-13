# EXPECT: ok
# Test that GC runs without crashing
gc_collect()
let a = [1, 2, 3]
let d = {"x": 1}
gc_collect()
print("ok")
