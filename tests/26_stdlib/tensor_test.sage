gc_disable()
# EXPECT: 6
# EXPECT: 3
# EXPECT: 2
# EXPECT: 6
# EXPECT: 21
# EXPECT: true
# EXPECT: 1
# EXPECT: 3

import ml.tensor

# Create tensor
let t = tensor.tensor([1, 2, 3, 4, 5, 6])
print t["size"]

# Zeros
let z = tensor.zeros([3])
print z["size"]

# Shape
let m = tensor.zeros([2, 3])
print m["ndim"]
print m["size"]

# Element-wise add
let a = tensor.tensor([1, 2, 3])
let b = tensor.tensor([4, 5, 6])
let c = tensor.add(a, b)
print tensor.sum_all(c)

# Matmul
let x = tensor.from_flat([1, 0, 0, 1], [2, 2])
let y = tensor.from_flat([5, 6, 7, 8], [2, 2])
let r = tensor.matmul(x, y)
print tensor.equal(r, y)

# Argmax
let v = tensor.tensor([0.1, 0.9, 0.3])
print tensor.argmax(v)

# Reshape
let rs = tensor.reshape(m, [3, 2])
print rs["shape"][0]
