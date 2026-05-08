# EXPECT: atomic_int_ok
# EXPECT: cas_ok
# EXPECT: exchange_ok
# EXPECT: flag_ok
# EXPECT: spinlock_ok
# EXPECT: counter_ok
# EXPECT: PASS
from std.atomic import atomic_int, load, store, add, sub, increment, decrement, cas, exchange
from std.atomic import atomic_flag, test_and_set, clear_flag
from std.atomic import create_spinlock, spin_lock, spin_unlock, spin_try_lock, is_locked
from std.atomic import counter, counter_add, counter_reset, counter_stats

# --- atomic_int ---
let a = atomic_int(10)
if load(a) == 10:
    store(a, 20)
    if load(a) == 20:
        add(a, 5)
        if load(a) == 25:
            sub(a, 3)
            if load(a) == 22:
                increment(a)
                decrement(a)
                if load(a) == 22:
                    print "atomic_int_ok"
                end
            end
        end
    end
end

# --- CAS ---
let b = atomic_int(5)
let swapped = cas(b, 5, 99)
let not_swapped = cas(b, 5, 0)  # value is now 99, not 5
if swapped == true and not_swapped == false and load(b) == 99:
    print "cas_ok"
end

# --- exchange ---
let c = atomic_int(7)
let old = exchange(c, 42)
if old == 7 and load(c) == 42:
    print "exchange_ok"
end

# --- atomic_flag ---
let f = atomic_flag()
let was_false = test_and_set(f)  # returns old (false), sets to true
let was_true = test_and_set(f)   # returns old (true)
clear_flag(f)
let after_clear = test_and_set(f)  # returns old (false) again
if was_false == false and was_true == true and after_clear == false:
    print "flag_ok"
end

# --- spinlock ---
let lk = create_spinlock()
if is_locked(lk) == false:
    spin_lock(lk)
    if is_locked(lk) == true:
        let try_fail = spin_try_lock(lk)  # already locked
        if try_fail == false:
            spin_unlock(lk)
            if is_locked(lk) == false:
                let try_ok = spin_try_lock(lk)
                if try_ok == true:
                    spin_unlock(lk)
                    print "spinlock_ok"
                end
            end
        end
    end
end

# --- counter with stats ---
let cnt = counter("hits")
counter_add(cnt, 10)
counter_add(cnt, 5)
counter_add(cnt, -3)
let st = counter_stats(cnt)
if st["value"] == 12 and st["max"] == 15 and st["ops"] == 3:
    counter_reset(cnt)
    let st2 = counter_stats(cnt)
    if st2["value"] == 0 and st2["ops"] == 0:
        print "counter_ok"
    end
end

print "PASS"
