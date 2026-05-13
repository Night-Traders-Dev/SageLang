# EXPECT: submit_ok
# EXPECT: run_all_ok
# EXPECT: parallel_map_ok
# EXPECT: multi_arg_ok
# EXPECT: error_handling_ok
# EXPECT: future_ok
# EXPECT: PASS
from std.threadpool import create, submit, run_all, get_result, pool_stats, parallel_map
from std.threadpool import create_future, resolve, reject, is_resolved, future_value

# --- submit and run_all ---
let pool = create(4)
proc double(x):
    return x * 2
end
let id1 = submit(pool, double, [5])
let id2 = submit(pool, double, [10])
let st0 = pool_stats(pool)
if st0["queued"] == 2:
    run_all(pool)
    let r1 = get_result(pool, id1)
    let r2 = get_result(pool, id2)
    if r1 == 10 and r2 == 20:
        print "submit_ok"
    end
end

# --- run_all clears queue ---
let pool2 = create(2)
proc add(a, b):
    return a + b
end
submit(pool2, add, [3, 4])
run_all(pool2)
let st2 = pool_stats(pool2)
if st2["queued"] == 0 and st2["completed"] == 1:
    print "run_all_ok"
end

# --- parallel_map ---
let pool3 = create(4)
proc square(x):
    return x * x
end
let results = parallel_map(pool3, square, [1, 2, 3, 4, 5])
if len(results) == 5:
    if results[0] == 1 and results[1] == 4 and results[2] == 9 and results[3] == 16 and results[4] == 25:
        print "parallel_map_ok"
    end
end

# --- 4-arg task (new fix) ---
let pool4 = create(1)
proc sum4(a, b, c, d):
    return a + b + c + d
end
let id4 = submit(pool4, sum4, [1, 2, 3, 4])
run_all(pool4)
let r4 = get_result(pool4, id4)
if r4 == 10:
    print "multi_arg_ok"
end

# --- error handling in tasks ---
let pool5 = create(1)
proc bad_fn():
    raise "intentional error"
end
let bad_id = submit(pool5, bad_fn, [])
run_all(pool5)
let st5 = pool_stats(pool5)
if st5["failed"] == 1 and st5["completed"] == 0:
    print "error_handling_ok"
end

# --- Future / Promise ---
let f = create_future()
if is_resolved(f) == false:
    resolve(f, 99)
    if is_resolved(f) == true:
        let val = future_value(f)
        if val == 99:
            # rejected future raises on future_value
            let f2 = create_future()
            reject(f2, "oops")
            let caught = false
            try:
                future_value(f2)
            catch e:
                caught = true
            end
            if caught:
                print "future_ok"
            end
        end
    end
end

print "PASS"
