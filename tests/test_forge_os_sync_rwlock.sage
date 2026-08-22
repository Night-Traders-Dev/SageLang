## Integration test for os.sync Read-Write Lock (rwlock) primitives.
import os.sync as sync
import assert

## Test basic read-write lock operations.
proc test_rwlock_basic():
    print "Testing os.sync rwlock basic operations..."
    let rw = sync.rwlock_create()

    # Acquire initial read lock
    assert.assert_true(sync.rwlock_try_read_lock(rw), "Should acquire first read lock")

    # Acquire second read lock
    assert.assert_true(sync.rwlock_try_read_lock(rw), "Should acquire second read lock")

    # Write lock must fail while readers exist
    assert.assert_false(sync.rwlock_try_write_lock(rw), "Write lock must fail when readers exist")

    # Release both read locks
    sync.rwlock_read_unlock(rw)
    sync.rwlock_read_unlock(rw)

    # Acquire write lock
    assert.assert_true(sync.rwlock_try_write_lock(rw), "Should acquire write lock")

    # Read and write lock must fail while writer exists
    assert.assert_false(sync.rwlock_try_read_lock(rw), "Read lock must fail when writer exists")
    assert.assert_false(sync.rwlock_try_write_lock(rw), "Second write lock must fail when writer exists")

    # Release write lock
    sync.rwlock_write_unlock(rw)

    # Re-acquire locks after unlock
    assert.assert_true(sync.rwlock_try_read_lock(rw), "Should acquire read lock after write unlock")
    sync.rwlock_read_unlock(rw)

    assert.assert_true(sync.rwlock_try_write_lock(rw), "Should acquire write lock after read unlock")
    sync.rwlock_write_unlock(rw)

    print "RwLock basic operations passed!"

## Main test runner.
proc main():
    test_rwlock_basic()
    print "All Forge os.sync rwlock tests passed!"

main()
