gc_disable()
# Loss functions for neural network training
#
# GPU acceleration: use cross_entropy_accel(ctx, logits, targets, batch, vocab)
# to route cross-entropy through gpu_accel backend.
# Standard functions run on CPU (pure Sage).

import math

# ============================================================================
# Mean Squared Error (MSE)
# ============================================================================

proc mse(predicted, target):
    let s = 0
    let n = predicted["size"]
    for i in range(n):
        let d = predicted["data"][i] - target["data"][i]
        s = s + d * d
    return s / n

# MSE gradient with respect to predicted
proc mse_grad(predicted, target):
    let n = predicted["size"]
    let data = []
    for i in range(n):
        push(data, 2 * (predicted["data"][i] - target["data"][i]) / n)
    let grad = {}
    grad["data"] = data
    grad["shape"] = predicted["shape"]
    grad["size"] = n
    grad["ndim"] = predicted["ndim"]
    return grad

# ============================================================================
# Cross-Entropy Loss
# ============================================================================

# Binary cross-entropy (predicted and target are tensors of probabilities)
proc binary_cross_entropy(predicted, target):
    let s = 0
    let n = predicted["size"]
    for i in range(n):
        let p = predicted["data"][i]
        let t = target["data"][i]
        # Clamp to avoid log(0)
        if p < 0.0000001:
            p = 0.0000001
        if p > 0.9999999:
            p = 0.9999999
        s = s - (t * math.log(p) + (1 - t) * math.log(1 - p))
    return s / n

# BCE gradient
proc binary_cross_entropy_grad(predicted, target):
    let n = predicted["size"]
    let data = []
    for i in range(n):
        let p = predicted["data"][i]
        let t = target["data"][i]
        if p < 0.0000001:
            p = 0.0000001
        if p > 0.9999999:
            p = 0.9999999
        push(data, (0 - t / p + (1 - t) / (1 - p)) / n)
    let grad = {}
    grad["data"] = data
    grad["shape"] = predicted["shape"]
    grad["size"] = n
    grad["ndim"] = predicted["ndim"]
    return grad

# Categorical cross-entropy (predicted = logits, target = class indices)
# Works on 1D (single sample) or 2D (batch)
proc cross_entropy(logits, targets):
    let data = logits["data"]
    let num_classes = logits["shape"][logits["ndim"] - 1]
    let batch = 1
    if logits["ndim"] == 2:
        batch = logits["shape"][0]
    let total_loss = 0
    for b in range(batch):
        let off = b * num_classes
        # Compute log-softmax for numerical stability
        let max_val = data[off]
        for j in range(num_classes):
            if data[off + j] > max_val:
                max_val = data[off + j]
        let log_sum = 0
        for j in range(num_classes):
            log_sum = log_sum + math.exp(data[off + j] - max_val)
        log_sum = max_val + math.log(log_sum)
        let target_class = targets["data"][b]
        total_loss = total_loss + (log_sum - data[off + target_class])
    return total_loss / batch

# ============================================================================
# Huber Loss (smooth L1)
# ============================================================================

proc huber(predicted, target, delta):
    let s = 0
    let n = predicted["size"]
    for i in range(n):
        let d = predicted["data"][i] - target["data"][i]
        if d < 0:
            d = 0 - d
        if d <= delta:
            s = s + 0.5 * d * d
        else:
            s = s + delta * (d - 0.5 * delta)
    return s / n

# ============================================================================
# L1 Loss (Mean Absolute Error)
# ============================================================================

proc l1(predicted, target):
    let s = 0
    let n = predicted["size"]
    for i in range(n):
        let d = predicted["data"][i] - target["data"][i]
        if d < 0:
            d = 0 - d
        s = s + d
    return s / n

# ============================================================================
# Hinge Loss (for SVM-style classification)
# ============================================================================

proc hinge(predicted, target):
    let s = 0
    let n = predicted["size"]
    for i in range(n):
        let margin = 1 - predicted["data"][i] * target["data"][i]
        if margin > 0:
            s = s + margin
    return s / n

# ============================================================================
# KL Divergence
# ============================================================================

proc kl_divergence(p_dist, q_dist):
    let s = 0
    let n = p_dist["size"]
    for i in range(n):
        let p = p_dist["data"][i]
        let q = q_dist["data"][i]
        if p > 0.0000001 and q > 0.0000001:
            s = s + p * math.log(p / q)
    return s

# ============================================================================
# GPU-accelerated variants
# ============================================================================

# Accelerated cross-entropy via gpu_accel (uses native C backend)
proc cross_entropy_accel(ctx, logits, targets, batch, vocab):
    import ml.gpu_accel
    return gpu_accel.cross_entropy(ctx, logits, targets, batch, vocab)

# Accelerated softmax via gpu_accel
proc softmax_accel(ctx, x, n):
    import ml.gpu_accel
    return gpu_accel.softmax(ctx, x, n)
