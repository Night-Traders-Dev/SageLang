gc_disable()
# EXPECT: true
# EXPECT: 2
# EXPECT: false
# EXPECT: true

import std.rwlock

let rw = rwlock.create()
rwlock.read_lock(rw)
rwlock.read_lock(rw)
print rwlock.is_read_locked(rw)
print rwlock.reader_count(rw)

# Can't write lock while readers
print rwlock.try_write_lock(rw)

rwlock.read_unlock(rw)
rwlock.read_unlock(rw)
print rwlock.try_write_lock(rw)
