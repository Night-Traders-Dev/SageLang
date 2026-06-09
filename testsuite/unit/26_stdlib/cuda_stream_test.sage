gc_disable()
# EXPECT: 0
# EXPECT: 1
# EXPECT: false
# EXPECT: true
# EXPECT: 2

import cuda.stream

let s = stream.default_stream()
print s["priority"]

stream.record_launch(s, "my_kernel", [4, 1, 1], [256, 1, 1])
print len(s["commands"])
print s["synchronized"]

stream.synchronize(s)
print s["synchronized"]

# Multi-stream plan
let plan = stream.create_plan()
let cs = stream.add_stream(plan, "compute", 0)
let ts = stream.add_stream(plan, "transfer", 0)
let stats = stream.plan_stats(plan)
print stats["num_streams"]
