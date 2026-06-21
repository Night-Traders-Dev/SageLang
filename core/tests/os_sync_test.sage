import os.sync
import assert

proc test_mutex():
    let m = sync.mutex_create()
    assert.assert_true(sync.mutex_try_lock(m), "Mutex try_lock failed")
    assert.assert_false(sync.mutex_try_lock(m), "Mutex try_lock should fail when locked")
    sync.mutex_unlock(m)
    assert.assert_true(sync.mutex_try_lock(m), "Mutex try_lock failed after unlock")
    sync.mutex_unlock(m)
    print "Mutex test passed"

proc test_rwlock_basic():
    let rw = sync.rwlock_create()

    # Test read lock
    assert.assert_true(sync.rwlock_try_read_lock(rw), "Read lock try failed")
    assert.assert_true(sync.rwlock_try_read_lock(rw), "Second read lock try failed")
    sync.rwlock_read_unlock(rw)
    sync.rwlock_read_unlock(rw)

    # Test write lock
    assert.assert_true(sync.rwlock_try_write_lock(rw), "Write lock try failed")
    assert.assert_false(sync.rwlock_try_read_lock(rw), "Read lock should fail when write locked")
    assert.assert_false(sync.rwlock_try_write_lock(rw), "Write lock should fail when write locked")
    sync.rwlock_write_unlock(rw)

    # Test transition
    assert.assert_true(sync.rwlock_try_read_lock(rw), "Read lock failed after write unlock")
    assert.assert_false(sync.rwlock_try_write_lock(rw), "Write lock should fail when read locked")
    sync.rwlock_read_unlock(rw)
    assert.assert_true(sync.rwlock_try_write_lock(rw), "Write lock failed after read unlock")
    sync.rwlock_write_unlock(rw)

    print "RwLock basic test passed"

proc test_main():
    test_mutex()
    test_rwlock_basic()
    print "All sync tests passed"

test_main()
