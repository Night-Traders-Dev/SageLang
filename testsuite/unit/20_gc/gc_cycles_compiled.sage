# RUN: compile-run
# EXPECT: true
# EXPECT: true
# Note on scope: the probe below allocates a value on purpose to give the
# collector a reason to run, which is right for a cycle test and wrong for a
# reclaim test -- it makes this file pass whether or not Env churn is ever
# reclaimed, because gc_alloc() is not on the path a call-heavy workload takes.
# gc_env_reclaim covers that case, and fails when the collector is unreachable.
let baseline_objects = gc_stats()["num_objects"]
let before_collections = gc_collections()

proc churn():
    let i = 0
    while i < 512:
        let cycle = []
        push(cycle, cycle)
        i = i + 1

churn()
let trigger = 0
while trigger < 8:
    let probe = "x" + "y"
    trigger = trigger + 1
let after_collections = gc_collections()
print after_collections > before_collections

gc_collect()
let after_objects = gc_stats()["num_objects"]
print after_objects <= baseline_objects + 8
