import os.sync
import assert

proc test_rwlock():
    print "Testing RwLock..."
    let rw = sync.rwlock_create()

    # Test read lock
    assert.assert_true(sync.rwlock_try_read_lock(rw), "Should acquire read lock")
    assert.assert_true(sync.rwlock_try_read_lock(rw), "Should acquire second read lock")

    # Test write lock fails when readers exist
    assert.assert_false(sync.rwlock_try_write_lock(rw), "Write lock should fail when readers exist")

    # Unlock readers
    sync.rwlock_read_unlock(rw)
    sync.rwlock_read_unlock(rw)

    # Test write lock
    assert.assert_true(sync.rwlock_try_write_lock(rw), "Should acquire write lock")
    assert.assert_false(sync.rwlock_try_read_lock(rw), "Read lock should fail when writer exists")
    assert.assert_false(sync.rwlock_try_write_lock(rw), "Second write lock should fail")

    # Unlock writer
    sync.rwlock_write_unlock(rw)

    # Test read lock again
    assert.assert_true(sync.rwlock_try_read_lock(rw), "Should acquire read lock after writer unlocks")
    sync.rwlock_read_unlock(rw)

    print "RwLock tests passed!"

proc test_mutex():
    print "Testing Mutex..."
    let m = sync.mutex_create()
    assert.assert_true(sync.mutex_try_lock(m), "Should acquire mutex")
    assert.assert_false(sync.mutex_try_lock(m), "Should not acquire locked mutex")
    sync.mutex_unlock(m)
    assert.assert_true(sync.mutex_try_lock(m), "Should acquire mutex after unlock")
    sync.mutex_unlock(m)
    print "Mutex tests passed!"

proc test_semaphore():
    print "Testing Semaphore..."
    let sem = sync.semaphore_create(2)
    assert.assert_true(sync.semaphore_try_wait(sem), "Should wait 1")
    assert.assert_true(sync.semaphore_try_wait(sem), "Should wait 2")
    assert.assert_false(sync.semaphore_try_wait(sem), "Should not wait 3")
    sync.semaphore_post(sem)
    assert.assert_true(sync.semaphore_try_wait(sem), "Should wait after post")
    print "Semaphore tests passed!"

test_rwlock()
test_mutex()
test_semaphore()
