gc_disable()
# EXPECT: true
# EXPECT: true
# EXPECT: 10

import std.profiler

let p = profiler.create()

proc work():
    let s = 0
    for i in range(100):
        s = s + i
    return s

profiler.begin(p, "work")
work()
profiler.end_section(p, "work")

let keys = dict_keys(p["entries"])
print len(keys) == 1

let entry = p["entries"]["work"]
print entry["call_count"] == 1

# Benchmark
proc add_fn():
    return 1 + 1

let result = profiler.bench("add", add_fn, 10)
print result["iterations"]
