gc_disable()
# EXPECT: linear
# EXPECT: 3
# EXPECT: sequential
# EXPECT: 4
# EXPECT: true
# EXPECT: 15

import ml.nn
import ml.tensor

# Linear layer
let l = nn.linear(4, 3)
print l["type"]

# Forward pass
let x = tensor.from_flat([1, 2, 3, 4], [4])
let y = nn.linear_forward(l, x)
print y["size"]

# Sequential model
let model = nn.sequential([nn.linear(4, 8), nn.relu_layer(), nn.linear(8, 3)])
print model["type"]

# Parameters
let params = nn.parameters(model)
print len(params)

# Forward through model
let out = nn.forward(model, x)
print out["size"] == 3

# Num parameters: 4*8 + 8 + 8*3 + 3 = 32+8+24+3 = 67... wait
# linear(4,8): weight=32, bias=8 = 40
# relu: 0
# linear(8,3): weight=24, bias=3 = 27
# but num_parameters only counts sequential->linear layers... let me check
# Actually: 4 params (w1, b1, w2, b2) -> total = 32+8+24+3 = 67? No, let me count:
# We have 2 linear layers -> 4 parameter tensors
# Sizes: 32, 8, 24, 3 but the test just prints param count
# Let me just print something predictable: len(params) = 4, total size...
# Actually let me test num_parameters for just a single layer
let single = nn.linear(4, 3)
print nn.num_parameters(single)
