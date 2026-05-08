# EXPECT: read_lock_ok
# EXPECT: write_lock_ok
# EXPECT: try_lock_ok
# EXPECT: scoped_read_ok
# EXPECT: scoped_write_ok
# EXPECT: stats_ok
# EXPECT: PASS
from std.rwlock import create, read_lock, read_unlock, write_lock, write_unlock
from std.rwlock import try_read_lock, try_write_lock, is_read_locked, is_write_locked
from std.rwlock import reader_count, stats, with_read, with_write

# --- multiple readers ---
let rw = create()
read_lock(rw)
read_lock(rw)
if reader_count(rw) == 2 and is_read_locked(rw):
    read_unlock(rw)
    read_unlock(rw)
    if reader_count(rw) == 0 and is_read_locked(rw) == false:
        print "read_lock_ok"
    end
end

# --- exclusive writer ---
let rw2 = create()
write_lock(rw2)
if is_write_locked(rw2):
    write_unlock(rw2)
    if is_write_locked(rw2) == false:
        print "write_lock_ok"
    end
end

# --- try_lock ---
let rw3 = create()
let r1 = try_read_lock(rw3)
let r2 = try_read_lock(rw3)
if r1 == true and r2 == true:
    # try_write_lock fails while readers hold
    let w1 = try_write_lock(rw3)
    if w1 == false:
        read_unlock(rw3)
        read_unlock(rw3)
        let w2 = try_write_lock(rw3)
        if w2 == true:
            # try_read_lock fails while writer holds
            let r3 = try_read_lock(rw3)
            if r3 == false:
                write_unlock(rw3)
                print "try_lock_ok"
            end
        end
    end
end

# --- with_read scoped helper ---
let rw4 = create()
let shared_data = 42
proc read_fn():
    return shared_data
end
let result = with_read(rw4, read_fn)
if result == 42 and is_read_locked(rw4) == false:
    print "scoped_read_ok"
end

# --- with_write scoped helper ---
let rw5 = create()
let counter = 0
proc write_fn():
    counter = counter + 10
    return counter
end
let wresult = with_write(rw5, write_fn)
if wresult == 10 and is_write_locked(rw5) == false:
    print "scoped_write_ok"
end

# --- stats ---
let rw6 = create()
read_lock(rw6)
read_lock(rw6)
read_unlock(rw6)
read_unlock(rw6)
write_lock(rw6)
write_unlock(rw6)
let st = stats(rw6)
if st["read_ops"] == 2 and st["write_ops"] == 1 and st["readers"] == 0 and st["writer"] == false:
    print "stats_ok"
end

print "PASS"
