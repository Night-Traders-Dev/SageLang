# EXPECT: 0
# EXPECT: 5
# EXPECT: true
# EXPECT: 10
# EXPECT: 20

let a = atomic_new(0)
print atomic_load(a)
atomic_add(a, 5)
print atomic_load(a)
print atomic_cas(a, 5, 10)
print atomic_exchange(a, 20)
print atomic_load(a)
