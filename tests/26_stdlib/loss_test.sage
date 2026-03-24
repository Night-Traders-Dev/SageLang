gc_disable()
# EXPECT: 0
# EXPECT: true
# EXPECT: true

import ml.loss
import ml.tensor

# MSE of identical tensors = 0
let a = tensor.tensor([1, 2, 3])
let b = tensor.tensor([1, 2, 3])
print loss.mse(a, b)

# MSE of different tensors > 0
let c = tensor.tensor([1, 2, 4])
print loss.mse(a, c) > 0

# L1 loss
print loss.l1(a, c) > 0
