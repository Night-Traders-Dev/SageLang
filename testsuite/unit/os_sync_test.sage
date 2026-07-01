import os.sync
import assert

let m = sync.mutex_create()

# Test 1: Initial try_lock
assert.assert_true(sync.mutex_try_lock(m), "First try_lock should succeed")

# Test 2: Concurrent try_lock (should fail)
assert.assert_false(sync.mutex_try_lock(m), "Second try_lock should fail")

# Test 3: Unlock and try_lock again
sync.mutex_unlock(m)
assert.assert_true(sync.mutex_try_lock(m), "try_lock after unlock should succeed")

# Test 4: Unlock
sync.mutex_unlock(m)

# Test 5: Standard lock/unlock
sync.mutex_lock(m)
sync.mutex_unlock(m)

print "Mutex smoke test passed!"

# RWLock Tests
let rw = sync.rwlock_create()

# Test 6: Initial read lock
assert.assert_true(sync.rwlock_try_read_lock(rw), "First read lock should succeed")

# Test 7: Concurrent read lock
assert.assert_true(sync.rwlock_try_read_lock(rw), "Second read lock should succeed")

# Test 8: Write lock should fail while read locks held
assert.assert_false(sync.rwlock_try_write_lock(rw), "Write lock should fail while readers exist")

# Test 9: Release read locks and get write lock
sync.rwlock_read_unlock(rw)
sync.rwlock_read_unlock(rw)
assert.assert_true(sync.rwlock_try_write_lock(rw), "Write lock should succeed after readers gone")

# Test 10: Read lock should fail while write lock held
assert.assert_false(sync.rwlock_try_read_lock(rw), "Read lock should fail while writer exists")

# Test 11: Release write lock and get read lock
sync.rwlock_write_unlock(rw)
assert.assert_true(sync.rwlock_try_read_lock(rw), "Read lock should succeed after writer gone")

print "RWLock smoke test passed!"
