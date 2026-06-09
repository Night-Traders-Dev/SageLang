gc_disable()
# EXPECT: 4096
# EXPECT: true
# EXPECT: 1024
# EXPECT: 4
# EXPECT: true

import cuda.memory

let a = memory.alloc(4096, 1)
print a["size"]
print a["allocated"]

let t = memory.alloc_typed(1024, "float32")
print t["count"]
print t["elem_size"]

# Memory pool
let pool = memory.create_pool(65536)
let p1 = memory.pool_alloc(pool, 1024)
let stats = memory.pool_stats(pool)
print stats["used"] == 1024
