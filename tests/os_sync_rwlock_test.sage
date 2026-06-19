import os.sync as sync

proc test_rwlock():
    let rw = sync.rwlock_create()

    # Test read lock
    if sync.rwlock_try_read_lock(rw) != true:
        raise "Failed to acquire read lock"
    if sync.rwlock_try_read_lock(rw) != true:
        raise "Failed to acquire second read lock"

    # Test write lock fails when readers active
    if sync.rwlock_try_write_lock(rw) == true:
        raise "Acquired write lock while readers active"

    # Unlock readers
    sync.rwlock_read_unlock(rw)
    sync.rwlock_read_unlock(rw)

    # Test write lock
    if sync.rwlock_try_write_lock(rw) != true:
        raise "Failed to acquire write lock"

    # Test read/write lock fails when writer active
    if sync.rwlock_try_read_lock(rw) == true:
        raise "Acquired read lock while writer active"
    if sync.rwlock_try_write_lock(rw) == true:
        raise "Acquired write lock while writer active"

    # Unlock writer
    sync.rwlock_write_unlock(rw)

    # Test re-acquire
    if sync.rwlock_try_read_lock(rw) != true:
        raise "Failed to re-acquire read lock"
    sync.rwlock_read_unlock(rw)
    if sync.rwlock_try_write_lock(rw) != true:
        raise "Failed to re-acquire write lock"
    sync.rwlock_write_unlock(rw)

    print "RwLock smoke test passed!"

test_rwlock()
