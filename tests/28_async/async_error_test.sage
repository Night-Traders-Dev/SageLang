# EXPECT: multi_await_ok
# EXPECT: await_non_thread_ok
# EXPECT: PASS
# Test async: multiple sequential awaits and await on a plain value

async proc safe_compute(x):
    return x * 3

# Multiple sequential awaits on independent async tasks
let t1 = safe_compute(2)
let t2 = safe_compute(3)
let t3 = safe_compute(4)
let r1 = await t1
let r2 = await t2
let r3 = await t3
if r1 == 6 and r2 == 9 and r3 == 12:
    print "multi_await_ok"
end

# await on a plain (non-thread) value returns it directly
let plain = 42
let r = await plain
if r == 42:
    print "await_non_thread_ok"
end

print "PASS"
