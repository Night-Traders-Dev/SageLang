gc_disable()
# EXPECT: sgd
# EXPECT: adam
# EXPECT: 0.01
# EXPECT: 0

import ml.optim

# Create fake parameters
let p1 = {}
p1["data"] = [1, 2, 3]
p1["size"] = 3
p1["grad"] = nil
let params = [p1]

let opt = optim.sgd(params, 0.01)
print opt["type"]

let adam_opt = optim.adam(params, 0.001)
print adam_opt["type"]
print opt["lr"]
print adam_opt["step_count"]
