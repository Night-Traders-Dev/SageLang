gc_disable()
# EXPECT: 4
# EXPECT: 0
# EXPECT: 1
# EXPECT: 3
# EXPECT: true
# EXPECT: true
# EXPECT: true

import ml_native

# Matmul identity
let C = ml_native.matmul([1,0,0,1], [3,4,5,6], 2, 2, 2)
print len(C)

# ReLU
let r = ml_native.relu([-1, 0, 1, 2])
print r[0]
print r[2]

# Softmax
let p = ml_native.softmax([1, 2, 3], 1, 3)
print len(p)

# Cross-entropy loss > 0
let loss = ml_native.cross_entropy([0.1, 0.9, 0.5, 0.3, 0.2, 0.7], [1, 2], 2, 3)
print loss > 0

# Benchmark produces results
let bench = ml_native.benchmark(32, 3)
print bench["gflops"] > 0

# Add
let s = ml_native.add([1, 2, 3], [4, 5, 6])
print s[0] == 5
