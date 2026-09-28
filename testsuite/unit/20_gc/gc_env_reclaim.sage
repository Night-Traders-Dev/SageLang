# EXPECT: true
# EXPECT: true
# EXPECT: 499500

# A call allocates an Env and a binding node, and those are malloc'd outside the
# value heap. For a long time nothing reclaimed them: gc_collect() was never
# scheduled for a workload made of calls, so memory grew in lockstep with the
# call count -- 96 bytes a call, 2.9 GB over a million emulated cycles, which is
# what made the test suites unrunnable in parallel.
#
# gc_cycles_compiled does not catch this, and cannot. It allocates a probe value
# afterwards specifically to give the collector a reason to run, so it passes
# whether or not call churn is reclaimed. There is deliberately no probe here.
# The only reason to collect is the call churn itself.

let before = gc_collections()

proc noop():
    return 0

var i = 0
while i < 150000:
    noop()
    i = i + 1

# 4 MB of Env churn is about 44,000 calls, so 150,000 should cross the threshold
# several times over.
print gc_collections() > before

# The other half. Collecting mid-churn once cost SageFS every directory entry in
# an unmounted area, because the collection ran while an Env was still being
# built and was not yet reachable from a root. So the values coming out of the
# interpreter afterwards have to be right, not merely present.
proc total(n):
    let acc = 0
    var k = 0
    while k < n:
        acc = acc + k
        k = k + 1
    return acc

print total(1000) == 499500
print total(1000)
