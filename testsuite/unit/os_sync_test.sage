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
