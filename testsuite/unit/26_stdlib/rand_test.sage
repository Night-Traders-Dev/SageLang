gc_disable()
# EXPECT: 16
# EXPECT: 36
# EXPECT: true
# EXPECT: true
# EXPECT: 10

import crypto.rand

let rng = rand.create(12345)

# Random bytes
let bytes = rand.random_bytes(rng, 16)
print len(bytes)

# UUID v4
let id = rand.uuid4(rng)
print len(id)

# Bounded random
let val = rand.next_bounded(rng, 100)
print val >= 0
print val < 100

# Random string
let s = rand.random_string(rng, 10)
print len(s)
