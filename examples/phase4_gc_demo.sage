# Phase 4 Feature Demonstration
# Garbage Collection and Memory Management

print "=== Phase 4: Garbage Collection ==="
print ""

# 1. Check initial GC stats
print "1. Initial GC Statistics:"
let stats = gc_stats()
print "Bytes allocated:"
print stats["bytes_allocated"]
print "Number of objects:"
print stats["num_objects"]
print ""

# 2. Create many objects to trigger GC
print "2. Creating many objects..."
let arrays = []
for i in range(100)
    let arr = [i, i+1, i+2, i+3, i+4]
    push(arrays, arr)

print "Created 100 arrays"
let stats2 = gc_stats()
print "Objects after creation:"
print stats2["num_objects"]
print ""

# 3. Manual garbage collection
print "3. Triggering manual GC..."
gc_collect()
let stats3 = gc_stats()
print "Collections performed:"
print stats3["collections"]
print "Objects freed:"
print stats3["objects_freed"]
print ""

# 4. Dictionary memory test
print "4. Dictionary memory test:"
let dicts = []
for i in range(50)
    let d = {"id": "test", "value": "data"}
    push(dicts, d)

print "Created 50 dictionaries"
let stats4 = gc_stats()
print "Current objects:"
print stats4["num_objects"]
print ""

# 5. Tuple memory test  
print "5. Tuple memory test:"
let tuples = []
for i in range(50)
    let t = (i, i * 2, i * 3)
    push(tuples, t)

print "Created 50 tuples"
let stats5 = gc_stats()
print "Current objects:"
print stats5["num_objects"]
print ""

# 6. Final GC stats
print "6. Final GC Statistics:"
let final_stats = gc_stats()
print "Total bytes allocated:"
print final_stats["bytes_allocated"]
print "Total objects:"
print final_stats["num_objects"]
print "Total collections:"
print final_stats["collections"]
print "Total objects freed:"
print final_stats["objects_freed"]
print "Next GC at (bytes):"
print final_stats["next_gc"]
print ""

print "=== GC Demo Complete! ==="
print "Note: GC automatically runs when memory threshold is exceeded"
print "Manual collection with gc_collect() for testing/debugging"
