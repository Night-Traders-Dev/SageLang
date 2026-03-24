gc_disable()
# EXPECT: 0
# EXPECT: 1
# EXPECT: true
# EXPECT: 3
# EXPECT: true

import std.condvar

let cv = condvar.create()
print condvar.waiter_count(cv)

condvar.wait(cv)
print condvar.waiter_count(cv)

condvar.notify(cv)
print condvar.is_notified(cv)

# Semaphore
let sem = condvar.create_semaphore(3)
print condvar.available_permits(sem)
condvar.acquire(sem)
condvar.acquire(sem)
print condvar.available_permits(sem) == 1
