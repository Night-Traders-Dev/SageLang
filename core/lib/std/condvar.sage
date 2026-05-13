gc_disable()
# Condition variable implementation
# Provides wait/notify/notify_all for thread synchronization patterns

proc create():
    let cv = {}
    cv["waiters"] = 0
    cv["notified"] = false
    cv["notify_count"] = 0
    cv["wait_count"] = 0
    return cv

# Wait on the condition (simulated — in real threading would block)
proc wait(cv):
    cv["waiters"] = cv["waiters"] + 1
    cv["wait_count"] = cv["wait_count"] + 1
    # In single-threaded Sage, we just record the wait
    cv["notified"] = false

# Notify one waiter
proc notify(cv):
    if cv["waiters"] > 0:
        cv["waiters"] = cv["waiters"] - 1
        cv["notified"] = true
    cv["notify_count"] = cv["notify_count"] + 1

# Notify all waiters
proc notify_all(cv):
    cv["notified"] = true
    cv["notify_count"] = cv["notify_count"] + cv["waiters"]
    cv["waiters"] = 0

# Check if notified
proc is_notified(cv):
    return cv["notified"]

# Number of waiting threads
proc waiter_count(cv):
    return cv["waiters"]

# Stats
proc stats(cv):
    let s = {}
    s["waiters"] = cv["waiters"]
    s["notified"] = cv["notified"]
    s["total_waits"] = cv["wait_count"]
    s["total_notifies"] = cv["notify_count"]
    return s

# ============================================================================
# Barrier (synchronization point for N threads)
# ============================================================================

proc create_barrier(count):
    let b = {}
    b["count"] = count
    b["waiting"] = 0
    b["generation"] = 0
    return b

proc barrier_wait(b):
    b["waiting"] = b["waiting"] + 1
    if b["waiting"] >= b["count"]:
        b["waiting"] = 0
        b["generation"] = b["generation"] + 1
        return true
    return false

proc barrier_reset(b):
    b["waiting"] = 0

# ============================================================================
# Latch (single-use barrier)
# ============================================================================

proc create_latch(count):
    let l = {}
    l["count"] = count
    l["released"] = false
    return l

proc latch_count_down(l):
    if l["count"] > 0:
        l["count"] = l["count"] - 1
    if l["count"] == 0:
        l["released"] = true

proc latch_is_released(l):
    return l["released"]

# ============================================================================
# Semaphore
# ============================================================================

proc create_semaphore(permits):
    let s = {}
    s["permits"] = permits
    s["max_permits"] = permits
    s["acquired_count"] = 0
    return s

proc acquire(sem):
    if sem["permits"] <= 0:
        raise "No permits available"
    sem["permits"] = sem["permits"] - 1
    sem["acquired_count"] = sem["acquired_count"] + 1

proc release(sem):
    if sem["permits"] < sem["max_permits"]:
        sem["permits"] = sem["permits"] + 1

proc try_acquire(sem):
    if sem["permits"] <= 0:
        return false
    sem["permits"] = sem["permits"] - 1
    sem["acquired_count"] = sem["acquired_count"] + 1
    return true

proc available_permits(sem):
    return sem["permits"]
