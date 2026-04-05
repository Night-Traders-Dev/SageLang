gc_disable()
# Tensor library - PyTorch-style tensor operations
# Supports N-dimensional tensors with shape tracking and broadcasting

import math

# ============================================================================
# Tensor creation
# ============================================================================

# Create a tensor from nested data with automatic shape inference
proc tensor(data):
    let t = {}
    t["data"] = flatten(data)
    t["shape"] = infer_shape(data)
    t["ndim"] = len(t["shape"])
    t["size"] = len(t["data"])
    t["requires_grad"] = false
    t["grad"] = nil
    t["_grad_fn"] = nil
    return t

# Create a tensor with explicit shape
proc from_flat(data, shape):
    let t = {}
    t["data"] = data
    t["shape"] = shape
    t["ndim"] = len(shape)
    let sz = 1
    for i in range(len(shape)):
        sz = sz * shape[i]
    t["size"] = sz
    t["requires_grad"] = false
    t["grad"] = nil
    t["_grad_fn"] = nil
    return t

# Create a zeros tensor
proc zeros(shape):
    let sz = 1
    for i in range(len(shape)):
        sz = sz * shape[i]
    let data = []
    for i in range(sz):
        push(data, 0)
    return from_flat(data, shape)

# Create a ones tensor
proc ones(shape):
    let sz = 1
    for i in range(len(shape)):
        sz = sz * shape[i]
    let data = []
    for i in range(sz):
        push(data, 1)
    return from_flat(data, shape)

# Create a tensor filled with a value
proc full(shape, value):
    let sz = 1
    for i in range(len(shape)):
        sz = sz * shape[i]
    let data = []
    for i in range(sz):
        push(data, value)
    return from_flat(data, shape)

# Create a 1D tensor with evenly spaced values
proc arange(start, stop, step):
    let data = []
    let val = start
    while val < stop:
        push(data, val)
        val = val + step
    return from_flat(data, [len(data)])

# Create a 1D tensor with n evenly spaced values
proc linspace(start, stop, n):
    let data = []
    if n <= 1:
        push(data, start)
        return from_flat(data, [1])
    let step = (stop - start) / (n - 1)
    for i in range(n):
        push(data, start + i * step)
    return from_flat(data, [n])

# Create an identity matrix
proc eye(n):
    let data = []
    for i in range(n):
        for j in range(n):
            if i == j:
                push(data, 1)
            else:
                push(data, 0)
    return from_flat(data, [n, n])

# Random tensor (uniform [0, 1))
proc rand_tensor(shape, rng_state):
    let sz = 1
    for i in range(len(shape)):
        sz = sz * shape[i]
    let data = []
    for i in range(sz):
        # Simple LCG for self-contained use
        rng_state["v"] = (rng_state["v"] * 1664525 + 1013904223) & 4294967295
        push(data, (rng_state["v"] & 65535) / 65536)
    return from_flat(data, shape)

# Random normal tensor (Box-Muller approximation)
proc randn_tensor(shape, rng_state):
    let t = rand_tensor(shape, rng_state)
    let data = t["data"]
    let i = 0
    while i + 1 < len(data):
        let u1 = data[i]
        let u2 = data[i + 1]
        if u1 < 0.0001:
            u1 = 0.0001
        let mag = math.sqrt(-2 * math.log(u1))
        data[i] = mag * math.cos(2 * math.pi * u2)
        data[i + 1] = mag * math.sin(2 * math.pi * u2)
        i = i + 2
    return t

# ============================================================================
# Shape utilities
# ============================================================================

proc infer_shape(data):
    if type(data) != "array":
        return []
    let shape = [len(data)]
    if len(data) > 0 and type(data[0]) == "array":
        let inner = infer_shape(data[0])
        for i in range(len(inner)):
            push(shape, inner[i])
    return shape

proc flatten(data):
    if type(data) != "array":
        return [data]
    let result = []
    for i in range(len(data)):
        if type(data[i]) == "array":
            let inner = flatten(data[i])
            for j in range(len(inner)):
                push(result, inner[j])
        else:
            push(result, data[i])
    return result

@inline
proc numel(t):
    return t["size"]

@inline
proc shape(t):
    return t["shape"]

@inline
proc ndim(t):
    return t["ndim"]

# Reshape tensor (must have same total size)
proc reshape(t, new_shape):
    let new_sz = 1
    for i in range(len(new_shape)):
        new_sz = new_sz * new_shape[i]
    if new_sz != t["size"]:
        return nil
    let result = from_flat(t["data"], new_shape)
    result["requires_grad"] = t["requires_grad"]
    return result

# Transpose a 2D tensor
proc transpose(t):
    if t["ndim"] != 2:
        return nil
    let rows = t["shape"][0]
    let cols = t["shape"][1]
    let data = []
    for j in range(cols):
        for i in range(rows):
            push(data, t["data"][i * cols + j])
    return from_flat(data, [cols, rows])

# ============================================================================
# Element-wise operations
# ============================================================================

proc add(a, b):
    let data = []
    for i in range(a["size"]):
        push(data, a["data"][i] + b["data"][i])
    return from_flat(data, a["shape"])

proc sub(a, b):
    let data = []
    for i in range(a["size"]):
        push(data, a["data"][i] - b["data"][i])
    return from_flat(data, a["shape"])

proc mul(a, b):
    let data = []
    for i in range(a["size"]):
        push(data, a["data"][i] * b["data"][i])
    return from_flat(data, a["shape"])

proc div_tensor(a, b):
    let data = []
    for i in range(a["size"]):
        push(data, a["data"][i] / b["data"][i])
    return from_flat(data, a["shape"])

# Scalar operations
proc add_scalar(t, s):
    let data = []
    for i in range(t["size"]):
        push(data, t["data"][i] + s)
    return from_flat(data, t["shape"])

proc mul_scalar(t, s):
    let data = []
    for i in range(t["size"]):
        push(data, t["data"][i] * s)
    return from_flat(data, t["shape"])

@inline
proc neg(t):
    return mul_scalar(t, -1)

proc pow_tensor(t, p):
    let data = []
    for i in range(t["size"]):
        push(data, math.pow(t["data"][i], p))
    return from_flat(data, t["shape"])

proc sqrt_tensor(t):
    let data = []
    for i in range(t["size"]):
        push(data, math.sqrt(t["data"][i]))
    return from_flat(data, t["shape"])

proc abs_tensor(t):
    let data = []
    for i in range(t["size"]):
        let v = t["data"][i]
        if v < 0:
            push(data, 0 - v)
        else:
            push(data, v)
    return from_flat(data, t["shape"])

proc exp_tensor(t):
    let data = []
    for i in range(t["size"]):
        push(data, math.exp(t["data"][i]))
    return from_flat(data, t["shape"])

proc log_tensor(t):
    let data = []
    for i in range(t["size"]):
        push(data, math.log(t["data"][i]))
    return from_flat(data, t["shape"])

# Clamp values to [lo, hi]
proc clamp(t, lo, hi):
    let data = []
    for i in range(t["size"]):
        let v = t["data"][i]
        if v < lo:
            push(data, lo)
        if v > hi:
            push(data, hi)
        if v >= lo and v <= hi:
            push(data, v)
    return from_flat(data, t["shape"])

# ============================================================================
# Reduction operations
# ============================================================================

proc sum_all(t):
    let s = 0
    for i in range(t["size"]):
        s = s + t["data"][i]
    return s

@inline
proc mean_all(t):
    return sum_all(t) / t["size"]

proc max_all(t):
    let m = t["data"][0]
    for i in range(t["size"]):
        if t["data"][i] > m:
            m = t["data"][i]
    return m

proc min_all(t):
    let m = t["data"][0]
    for i in range(t["size"]):
        if t["data"][i] < m:
            m = t["data"][i]
    return m

proc argmax(t):
    let m = t["data"][0]
    let idx = 0
    for i in range(t["size"]):
        if t["data"][i] > m:
            m = t["data"][i]
            idx = i
    return idx

proc argmin(t):
    let m = t["data"][0]
    let idx = 0
    for i in range(t["size"]):
        if t["data"][i] < m:
            m = t["data"][i]
            idx = i
    return idx

# ============================================================================
# Matrix operations
# ============================================================================

# Matrix multiply (2D tensors only)
proc matmul(a, b):
    if a["ndim"] != 2 or b["ndim"] != 2:
        return nil
    let m = a["shape"][0]
    let k = a["shape"][1]
    let n = b["shape"][1]
    if k != b["shape"][0]:
        return nil
    let data = []
    for i in range(m):
        for j in range(n):
            let s = 0
            for p in range(k):
                s = s + a["data"][i * k + p] * b["data"][p * n + j]
            push(data, s)
    return from_flat(data, [m, n])

# Dot product of 1D tensors
proc dot(a, b):
    let s = 0
    for i in range(a["size"]):
        s = s + a["data"][i] * b["data"][i]
    return s

# L2 norm
proc norm(t):
    let s = 0
    for i in range(t["size"]):
        s = s + t["data"][i] * t["data"][i]
    return math.sqrt(s)

# ============================================================================
# Activation functions (element-wise)
# ============================================================================

proc relu(t):
    let data = []
    for i in range(t["size"]):
        let v = t["data"][i]
        if v > 0:
            push(data, v)
        else:
            push(data, 0)
    return from_flat(data, t["shape"])

proc sigmoid(t):
    let data = []
    for i in range(t["size"]):
        push(data, 1 / (1 + math.exp(0 - t["data"][i])))
    return from_flat(data, t["shape"])

proc tanh_tensor(t):
    let data = []
    for i in range(t["size"]):
        let e_pos = math.exp(t["data"][i])
        let e_neg = math.exp(0 - t["data"][i])
        push(data, (e_pos - e_neg) / (e_pos + e_neg))
    return from_flat(data, t["shape"])

# Softmax along the last dimension (for 1D or rows of 2D)
proc softmax(t):
    let data = t["data"]
    let m = max_all(t)
    let exps = []
    let s = 0
    for i in range(t["size"]):
        let e = math.exp(data[i] - m)
        push(exps, e)
        s = s + e
    let result = []
    for i in range(t["size"]):
        push(result, exps[i] / s)
    return from_flat(result, t["shape"])

# ============================================================================
# Indexing
# ============================================================================

# Get element at flat index
@inline
proc item(t, idx):
    return t["data"][idx]

# Get row from 2D tensor
proc get_row(t, row):
    if t["ndim"] != 2:
        return nil
    let cols = t["shape"][1]
    let data = []
    for j in range(cols):
        push(data, t["data"][row * cols + j])
    return from_flat(data, [cols])

# Set element at flat index
@inline
proc set_item(t, idx, val):
    t["data"][idx] = val

# ============================================================================
# Comparison
# ============================================================================

proc equal(a, b):
    if a["size"] != b["size"]:
        return false
    for i in range(a["size"]):
        if a["data"][i] != b["data"][i]:
            return false
    return true

proc allclose(a, b, tol):
    if a["size"] != b["size"]:
        return false
    for i in range(a["size"]):
        let diff = a["data"][i] - b["data"][i]
        if diff < 0:
            diff = 0 - diff
        if diff > tol:
            return false
    return true

# ============================================================================
# Autograd support
# ============================================================================

@inline
proc requires_grad_(t):
    t["requires_grad"] = true
    return t

@inline
proc detach(t):
    let result = from_flat(t["data"], t["shape"])
    result["requires_grad"] = false
    return result

proc zero_grad(t):
    if t["grad"] != nil:
        let data = t["grad"]["data"]
        for i in range(len(data)):
            data[i] = 0
