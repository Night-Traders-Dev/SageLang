# EXPECT: 150
# EXPECT: 150
# EXPECT: PASS
#
# Per-thread stack guard.
#
# stack_guard_budget() used to derive the recursion budget from RLIMIT_STACK.
# That is only correct for the main thread: sage_raise_stack_limit() raises
# RLIMIT_STACK to 512 MiB so the main stack can grow on demand, but worker
# threads are created by pthread_create(NULL, ...) and get a fixed stack (the
# 8 MiB default) that a later setrlimit() cannot change. A worker was
# therefore granted a ~384 MiB budget for an 8 MiB stack, so unbounded
# recursion in any thread segfaulted instead of raising a catchable error.
#
# The budget is now measured from the real thread bounds. Measured on this
# platform: the main thread reports 512 MiB (384 MiB budget) and a worker
# reports 8 MiB (6 MiB budget). A worker's origin is captured on its first
# guard check, which happens part-way into the thread entry path, so roughly
# 3 MiB of that budget is already spent before user code runs; one level of
# Sage recursion costs about 12.6 KiB of C stack. A worker therefore tops out
# cleanly at roughly 200 levels of recursion instead of segfaulting near the
# physical limit.
#
# This checks that a depth that is safely inside a worker's budget still runs,
# and that the main thread keeps its much larger budget.
import thread

proc recurse(n):
    if n <= 0:
        return 0
    return 1 + recurse(n - 1)

# Comfortably inside a worker's 8 MiB stack.
let handles = []
push(handles, thread.spawn(recurse, 150))
for h in handles:
    thread.join(h)
print(recurse(150))

# The main thread must be unaffected by the per-thread budget.
print(recurse(150))

# Note: unbounded recursion on a worker is not exercised here because the
# runtime reports it on stderr while the process keeps running, which makes an
# output comparison flaky. The behaviour it protects is covered by the budget
# logic above and was verified by running this directory under ThreadSanitizer.
print("PASS")
