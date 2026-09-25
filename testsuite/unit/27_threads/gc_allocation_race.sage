# EXPECT: 900
# EXPECT: PASS
#
# Concurrent allocation stress: four worker threads allocate heavily while the
# main thread allocates at the same time, so collections are triggered from
# several threads and the GC root-scans stacks owned by other threads.
#
# This exercises three things that were previously unsynchronized:
#   * allocation accounting (bytes_allocated/bytes_freed) is updated both
#     under the GC mutex and, lock-free, from array/buffer growth;
#   * the per-thread AST temp stacks are written by their owning thread while
#     the collector reads them during a root scan;
#   * a temporary pushed and popped entirely inside the concurrent-mark
#     window must still survive (write barrier cannot see temp-stack pushes,
#     so the push itself shades).
#
# The race is only *reported* under ThreadSanitizer; run it with:
#   ./sagemake --tsan
#   ./core/build_sage_tsan/sage testsuite/unit/27_threads/gc_allocation_race.sage
import thread
from std.atomic import atomic_int, add, load

let counter = atomic_int(0)

proc worker(id):
    for i in range(0, 300):
        let junk = []
        for k in range(0, 60):
            push(junk, "w" + str(id) + "-" + str(k) + "-" + str(i))
        add(counter, 1)

let handles = []
push(handles, thread.spawn(worker, 1))
push(handles, thread.spawn(worker, 2))
push(handles, thread.spawn(worker, 3))

for i in range(0, 800):
    let live = []
    for k in range(0, 50):
        push(live, ["m", i, k, "payload"])

for handle in handles:
    thread.join(handle)

print(load(counter))
print("PASS")
