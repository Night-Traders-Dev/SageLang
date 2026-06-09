gc_disable()
# EXPECT: 5
# EXPECT: true
# EXPECT: true
# EXPECT: true

import ml.debug

let weights = [0.1, -0.2, 0.3, -0.4, 0.5]
let stats = debug.weight_stats(weights)
print stats["count"]
print stats["mean"] > -0.1

# Histogram
let hist = debug.histogram(weights, 5)
print len(hist["counts"]) == 5

# Training diagnosis
let losses = [5.0, 4.5, 4.2, 4.0, 3.8, 3.6]
let issues = debug.diagnose_training(losses)
print len(issues) > 0
