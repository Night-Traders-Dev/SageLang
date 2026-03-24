gc_disable()
# Read-Write Lock implementation
# Multiple concurrent readers OR one exclusive writer

proc create():
    let lock = {}
    lock["readers"] = 0
    lock["writer"] = false
    lock["write_waiters"] = 0
    lock["read_ops"] = 0
    lock["write_ops"] = 0
    return lock

proc read_lock(rw):
    if rw["writer"]:
        raise "Cannot acquire read lock while writer holds lock"
    rw["readers"] = rw["readers"] + 1
    rw["read_ops"] = rw["read_ops"] + 1

proc read_unlock(rw):
    if rw["readers"] > 0:
        rw["readers"] = rw["readers"] - 1

proc write_lock(rw):
    if rw["writer"]:
        raise "Cannot acquire write lock: already held"
    if rw["readers"] > 0:
        raise "Cannot acquire write lock while readers hold lock"
    rw["writer"] = true
    rw["write_ops"] = rw["write_ops"] + 1

proc write_unlock(rw):
    rw["writer"] = false

proc try_read_lock(rw):
    if rw["writer"]:
        return false
    rw["readers"] = rw["readers"] + 1
    rw["read_ops"] = rw["read_ops"] + 1
    return true

proc try_write_lock(rw):
    if rw["writer"] or rw["readers"] > 0:
        return false
    rw["writer"] = true
    rw["write_ops"] = rw["write_ops"] + 1
    return true

proc is_read_locked(rw):
    return rw["readers"] > 0

proc is_write_locked(rw):
    return rw["writer"]

proc reader_count(rw):
    return rw["readers"]

proc stats(rw):
    let s = {}
    s["readers"] = rw["readers"]
    s["writer"] = rw["writer"]
    s["read_ops"] = rw["read_ops"]
    s["write_ops"] = rw["write_ops"]
    return s

# ============================================================================
# Scoped lock helpers (use with try/finally)
# ============================================================================

proc with_read(rw, fn):
    read_lock(rw)
    try:
        let result = fn()
        read_unlock(rw)
        return result
    catch e:
        read_unlock(rw)
        raise e

proc with_write(rw, fn):
    write_lock(rw)
    try:
        let result = fn()
        write_unlock(rw)
        return result
    catch e:
        write_unlock(rw)
        raise e
