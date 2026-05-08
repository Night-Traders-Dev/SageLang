# EXPECT: condvar_ok
# EXPECT: barrier_ok
# EXPECT: latch_ok
# EXPECT: semaphore_ok
# EXPECT: PASS
from std.condvar import create, wait, notify, notify_all, is_notified, waiter_count, stats
from std.condvar import create_barrier, barrier_wait, barrier_reset
from std.condvar import create_latch, latch_count_down, latch_is_released
from std.condvar import create_semaphore, acquire, release, try_acquire, available_permits

# --- condvar ---
let cv = create()
wait(cv)
wait(cv)
if waiter_count(cv) == 2:
    notify(cv)
    if waiter_count(cv) == 1 and is_notified(cv):
        notify_all(cv)
        if waiter_count(cv) == 0:
            let st = stats(cv)
            if st["total_waits"] == 2 and st["total_notifies"] >= 2:
                print "condvar_ok"
            end
        end
    end
end

# --- barrier ---
let b = create_barrier(3)
let r1 = barrier_wait(b)  # 1st — not released
let r2 = barrier_wait(b)  # 2nd — not released
let r3 = barrier_wait(b)  # 3rd — released, resets
if r1 == false and r2 == false and r3 == true:
    # After release, waiting resets to 0 — next cycle works
    let r4 = barrier_wait(b)
    if r4 == false:
        print "barrier_ok"
    end
end

# --- latch ---
let l = create_latch(3)
if latch_is_released(l) == false:
    latch_count_down(l)
    latch_count_down(l)
    if latch_is_released(l) == false:
        latch_count_down(l)
        if latch_is_released(l) == true:
            # Extra count_down on released latch is a no-op (count stays 0)
            latch_count_down(l)
            if latch_is_released(l) == true:
                print "latch_ok"
            end
        end
    end
end

# --- semaphore ---
let sem = create_semaphore(3)
if available_permits(sem) == 3:
    acquire(sem)
    acquire(sem)
    if available_permits(sem) == 1:
        let got = try_acquire(sem)
        if got == true and available_permits(sem) == 0:
            let fail = try_acquire(sem)  # no permits left
            if fail == false:
                release(sem)
                release(sem)
                release(sem)
                # Should not exceed max_permits
                release(sem)
                if available_permits(sem) == 3:
                    print "semaphore_ok"
                end
            end
        end
    end
end

print "PASS"
