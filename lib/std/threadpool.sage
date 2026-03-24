gc_disable()
# Thread pool for parallel task execution
# Provides work queue, task submission, and result collection

# ============================================================================
# Task definitions
# ============================================================================

let TASK_PENDING = 0
let TASK_RUNNING = 1
let TASK_COMPLETE = 2
let TASK_FAILED = 3

proc create_task(id, fn, args):
    let task = {}
    task["id"] = id
    task["fn"] = fn
    task["args"] = args
    task["status"] = 0
    task["result"] = nil
    task["error"] = nil
    return task

# ============================================================================
# Thread pool
# ============================================================================

proc create(num_workers):
    let pool = {}
    pool["num_workers"] = num_workers
    pool["queue"] = []
    pool["results"] = {}
    pool["next_id"] = 1
    pool["completed"] = 0
    pool["failed"] = 0
    return pool

# Submit a task to the pool
proc submit(pool, fn, args):
    let task_id = pool["next_id"]
    pool["next_id"] = pool["next_id"] + 1
    let task = create_task(task_id, fn, args)
    push(pool["queue"], task)
    return task_id

# Execute all queued tasks synchronously (simulated pool)
proc run_all(pool):
    let queue = pool["queue"]
    for i in range(len(queue)):
        let task = queue[i]
        task["status"] = 1
        try:
            let args = task["args"]
            let result = nil
            if len(args) == 0:
                result = task["fn"]()
            if len(args) == 1:
                result = task["fn"](args[0])
            if len(args) == 2:
                result = task["fn"](args[0], args[1])
            if len(args) == 3:
                result = task["fn"](args[0], args[1], args[2])
            task["result"] = result
            task["status"] = 2
            pool["results"][str(task["id"])] = result
            pool["completed"] = pool["completed"] + 1
        catch e:
            task["error"] = e
            task["status"] = 3
            pool["failed"] = pool["failed"] + 1
    pool["queue"] = []

# Get result for a task
proc get_result(pool, task_id):
    let key = str(task_id)
    if dict_has(pool["results"], key):
        return pool["results"][key]
    return nil

# Get pool statistics
proc pool_stats(pool):
    let s = {}
    s["workers"] = pool["num_workers"]
    s["queued"] = len(pool["queue"])
    s["completed"] = pool["completed"]
    s["failed"] = pool["failed"]
    return s

# ============================================================================
# Parallel map
# ============================================================================

# Apply fn to each element, collect results
proc parallel_map(pool, fn, items):
    let ids = []
    for i in range(len(items)):
        push(ids, submit(pool, fn, [items[i]]))
    run_all(pool)
    let results = []
    for i in range(len(ids)):
        push(results, get_result(pool, ids[i]))
    return results

# ============================================================================
# Future / Promise pattern
# ============================================================================

proc create_future():
    let f = {}
    f["resolved"] = false
    f["value"] = nil
    f["error"] = nil
    return f

proc resolve(future, value):
    future["resolved"] = true
    future["value"] = value

proc reject(future, error):
    future["resolved"] = true
    future["error"] = error

proc is_resolved(future):
    return future["resolved"]

proc future_value(future):
    if not future["resolved"]:
        raise "Future not yet resolved"
    if future["error"] != nil:
        raise future["error"]
    return future["value"]
