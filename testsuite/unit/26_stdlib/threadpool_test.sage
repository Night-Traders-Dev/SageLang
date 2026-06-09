gc_disable()
# EXPECT: 4
# EXPECT: 2
# EXPECT: 0
# EXPECT: true

import std.threadpool

proc square(x):
    return x * x

let pool = threadpool.create(4)
let id1 = threadpool.submit(pool, square, [3])
let id2 = threadpool.submit(pool, square, [5])
threadpool.run_all(pool)

print pool["num_workers"]
print pool["completed"]
print pool["failed"]
print threadpool.get_result(pool, id2) == 25
