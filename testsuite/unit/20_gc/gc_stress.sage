# EXPECT: 100
# EXPECT: ok
# Stress test: allocate many objects and force GC
var count = 0
for i in range(100):
    let arr = [1, 2, 3, 4, 5]
    let d = {"a": i, "b": i + 1}
    count = count + 1
gc_collect()
print(count)
print("ok")
