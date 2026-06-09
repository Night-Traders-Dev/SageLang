gc_disable()
# EXPECT: 0
# EXPECT: 5
# EXPECT: true
# EXPECT: false
# EXPECT: 10

import std.atomic

let a = atomic.atomic_int(0)
print atomic.load(a)

atomic.add(a, 5)
print atomic.load(a)

# CAS
print atomic.cas(a, 5, 10)
print atomic.cas(a, 5, 20)
print atomic.load(a)
