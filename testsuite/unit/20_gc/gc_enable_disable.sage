# EXPECT: ok
gc_disable()
let a = [1, 2, 3]
gc_enable()
gc_collect()
print("ok")
