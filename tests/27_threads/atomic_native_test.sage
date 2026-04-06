# EXPECT: 0
# EXPECT: 5
# EXPECT: true
# EXPECT: 10
# Test: True C-level atomic operations
let a = atomic_new(0)
print atomic_load(a)

# Atomic add
atomic_add(a, 5)
print atomic_load(a)

# Atomic CAS
let ok = atomic_cas(a, 5, 10)
print ok

print atomic_load(a)
