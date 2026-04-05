gc_disable()
# Atomic-like operations (simulated for single-threaded Sage)
# Provides compare-and-swap, atomic counters, and spin locks

# ============================================================================
# Atomic integer
# ============================================================================

proc atomic_int(initial):
    let a = {}
    a["value"] = initial
    return a

@inline
proc load(atom):
    return atom["value"]

@inline
proc store(atom, value):
    atom["value"] = value

@inline
proc add(atom, delta):
    atom["value"] = atom["value"] + delta
    return atom["value"]

@inline
proc sub(atom, delta):
    atom["value"] = atom["value"] - delta
    return atom["value"]

@inline
proc increment(atom):
    return add(atom, 1)

@inline
proc decrement(atom):
    return sub(atom, 1)

# Compare-and-swap: if current == expected, set to new_val, return old
proc cas(atom, expected, new_val):
    let old = atom["value"]
    if old == expected:
        atom["value"] = new_val
        return true
    return false

proc exchange(atom, new_val):
    let old = atom["value"]
    atom["value"] = new_val
    return old

# ============================================================================
# Atomic flag (boolean)
# ============================================================================

proc atomic_flag():
    let f = {}
    f["value"] = false
    return f

@inline
proc test_and_set(flag):
    let old = flag["value"]
    flag["value"] = true
    return old

@inline
proc clear_flag(flag):
    flag["value"] = false

# ============================================================================
# Spin lock (based on atomic flag)
# ============================================================================

proc create_spinlock():
    let lock = {}
    lock["locked"] = false
    lock["owner"] = nil
    return lock

proc spin_lock(lock):
    # In single-threaded Sage, this just sets the flag
    lock["locked"] = true

proc spin_unlock(lock):
    lock["locked"] = false

proc spin_try_lock(lock):
    if lock["locked"]:
        return false
    lock["locked"] = true
    return true

@inline
proc is_locked(lock):
    return lock["locked"]

# ============================================================================
# Atomic counter with stats
# ============================================================================

proc counter(name):
    let c = {}
    c["name"] = name
    c["value"] = 0
    c["max"] = 0
    c["min"] = 0
    c["ops"] = 0
    return c

proc counter_add(c, delta):
    c["value"] = c["value"] + delta
    c["ops"] = c["ops"] + 1
    if c["value"] > c["max"]:
        c["max"] = c["value"]
    if c["value"] < c["min"]:
        c["min"] = c["value"]
    return c["value"]

proc counter_reset(c):
    c["value"] = 0
    c["ops"] = 0

proc counter_stats(c):
    let s = {}
    s["name"] = c["name"]
    s["value"] = c["value"]
    s["max"] = c["max"]
    s["min"] = c["min"]
    s["ops"] = c["ops"]
    return s

# ============================================================================
# Memory ordering constants (documentation only — Sage is single-threaded)
# ============================================================================

comptime:
    let RELAXED = 0
    let ACQUIRE = 1
    let RELEASE = 2
    let ACQ_REL = 3
    let SEQ_CST = 4
