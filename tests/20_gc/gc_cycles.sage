# EXPECT: true
# EXPECT: true
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
