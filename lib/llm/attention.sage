gc_disable()
# Multi-head self-attention mechanisms
# Supports causal (autoregressive), cross-attention, and grouped-query attention
#
# GPU acceleration: use scaled_dot_product_accel() with a gpu_accel context
# for GPU/NPU/TPU offload of Q@K^T matmul and softmax.
# The standard scaled_dot_product() always runs on CPU (pure Sage).

import math

# ============================================================================
# Attention computation
# ============================================================================

# Scaled dot-product attention for a single head
# q, k, v: flat arrays of shape [seq_len * d_head]
# Returns: flat array [seq_len * d_head]
proc scaled_dot_product(q, k, v, seq_len, d_head, causal):
    let scale = 1.0 / math.sqrt(d_head)
    # Compute attention scores: Q @ K^T / sqrt(d_k)
    let scores = []
    for i in range(seq_len):
        for j in range(seq_len):
            let s = 0
            for d in range(d_head):
                s = s + q[i * d_head + d] * k[j * d_head + d]
            s = s * scale
            # Causal mask: positions can only attend to earlier positions
            if causal and j > i:
                s = -10000
            push(scores, s)
    # Softmax per row
    let attn_weights = []
    for i in range(seq_len):
        let max_val = scores[i * seq_len]
        for j in range(seq_len):
            if scores[i * seq_len + j] > max_val:
                max_val = scores[i * seq_len + j]
        let exp_sum = 0
        let row_exps = []
        for j in range(seq_len):
            let e = math.exp(scores[i * seq_len + j] - max_val)
            push(row_exps, e)
            exp_sum = exp_sum + e
        for j in range(seq_len):
            push(attn_weights, row_exps[j] / exp_sum)
    # Apply attention to values: weights @ V
    let output = []
    for i in range(seq_len):
        for d in range(d_head):
            let s = 0
            for j in range(seq_len):
                s = s + attn_weights[i * seq_len + j] * v[j * d_head + d]
            push(output, s)
    return output

# GPU-accelerated scaled dot-product attention
# Routes matmul and softmax through gpu_accel context
# ctx: gpu_accel context (from gpu_accel.create())
# Falls back to CPU ml_native when GPU unavailable
proc scaled_dot_product_accel(ctx, q, k, v, seq_len, d_head, causal):
    # Q@K^T via accelerated matmul: [seq_len x d_head] @ [d_head x seq_len]
    # We need K transposed, so build it
    let kt = []
    for j in range(d_head):
        for i in range(seq_len):
            push(kt, k[i * d_head + j])
    # Import here to avoid circular dependency at module level
    import ml.gpu_accel
    let scores_raw = gpu_accel.matmul(ctx, q, kt, seq_len, d_head, seq_len)
    # Scale
    let scale = 1.0 / math.sqrt(d_head)
    scores_raw = gpu_accel.scale(ctx, scores_raw, scale)
    # Causal mask
    if causal:
        for i in range(seq_len):
            for j in range(seq_len):
                if j > i:
                    scores_raw[i * seq_len + j] = -10000
    # Softmax per row
    let attn_weights = []
    for i in range(seq_len):
        let row = []
        for j in range(seq_len):
            push(row, scores_raw[i * seq_len + j])
        let soft = gpu_accel.softmax(ctx, row, seq_len)
        for j in range(seq_len):
            push(attn_weights, soft[j])
    # Attn @ V via accelerated matmul: [seq_len x seq_len] @ [seq_len x d_head]
    return gpu_accel.matmul(ctx, attn_weights, v, seq_len, seq_len, d_head)

# ============================================================================
# Linear projections
# ============================================================================

# Create weight matrix for Q/K/V projection
proc create_projection(d_model, d_out):
    let proj = {}
    proj["d_in"] = d_model
    proj["d_out"] = d_out
    let scale = 1.0 / math.sqrt(d_model)
    let weight = []
    let seed = d_model * 17 + d_out * 31
    for i in range(d_model * d_out):
        seed = (seed * 1664525 + 1013904223) & 4294967295
        push(weight, ((seed & 65535) / 65536 - 0.5) * 2 * scale)
    proj["weight"] = weight
    let bias = []
    for i in range(d_out):
        push(bias, 0)
    proj["bias"] = bias
    return proj

# Apply linear projection: x @ W^T + b
# x: [seq_len * d_in], returns [seq_len * d_out]
proc project(proj, x, seq_len):
    let d_in = proj["d_in"]
    let d_out = proj["d_out"]
    let w = proj["weight"]
    let b = proj["bias"]
    let result = []
    for i in range(seq_len):
        for j in range(d_out):
            let s = b[j]
            for k in range(d_in):
                s = s + x[i * d_in + k] * w[j * d_in + k]
            push(result, s)
    return result

# ============================================================================
# Multi-Head Attention
# ============================================================================

proc create_mha(d_model, n_heads):
    let mha = {}
    mha["d_model"] = d_model
    mha["n_heads"] = n_heads
    mha["d_head"] = (d_model / n_heads) | 0
    mha["q_proj"] = create_projection(d_model, d_model)
    mha["k_proj"] = create_projection(d_model, d_model)
    mha["v_proj"] = create_projection(d_model, d_model)
    mha["o_proj"] = create_projection(d_model, d_model)
    return mha

# Forward pass through multi-head attention
# x: flat array [seq_len * d_model]
proc mha_forward(mha, x, seq_len, causal):
    let d_model = mha["d_model"]
    let n_heads = mha["n_heads"]
    let d_head = mha["d_head"]
    # Project to Q, K, V
    let q = project(mha["q_proj"], x, seq_len)
    let k = project(mha["k_proj"], x, seq_len)
    let v = project(mha["v_proj"], x, seq_len)
    # Split into heads and compute attention per head
    let head_outputs = []
    for h in range(n_heads):
        let qh = []
        let kh = []
        let vh = []
        for i in range(seq_len):
            for d in range(d_head):
                push(qh, q[i * d_model + h * d_head + d])
                push(kh, k[i * d_model + h * d_head + d])
                push(vh, v[i * d_model + h * d_head + d])
        let head_out = scaled_dot_product(qh, kh, vh, seq_len, d_head, causal)
        push(head_outputs, head_out)
    # Concatenate heads
    let concat = []
    for i in range(seq_len):
        for h in range(n_heads):
            for d in range(d_head):
                push(concat, head_outputs[h][i * d_head + d])
    # Output projection
    return project(mha["o_proj"], concat, seq_len)

# ============================================================================
# Causal attention mask
# ============================================================================

proc causal_mask(seq_len):
    let mask = []
    for i in range(seq_len):
        for j in range(seq_len):
            if j <= i:
                push(mask, 0)
            else:
                push(mask, -10000)
    return mask

# ============================================================================
# KV Cache for efficient autoregressive generation
# ============================================================================

proc create_kv_cache(n_layers, n_heads, d_head):
    let cache = {}
    cache["n_layers"] = n_layers
    cache["keys"] = []
    cache["values"] = []
    for i in range(n_layers):
        push(cache["keys"], [])
        push(cache["values"], [])
    cache["seq_len"] = 0
    return cache

proc cache_append(cache, layer, new_k, new_v):
    let layer_keys = cache["keys"][layer]
    let layer_vals = cache["values"][layer]
    for i in range(len(new_k)):
        push(layer_keys, new_k[i])
    for i in range(len(new_v)):
        push(layer_vals, new_v[i])

proc cache_get_keys(cache, layer):
    return cache["keys"][layer]

proc cache_get_values(cache, layer):
    return cache["values"][layer]

proc cache_clear(cache):
    for i in range(cache["n_layers"]):
        cache["keys"][i] = []
        cache["values"][i] = []
    cache["seq_len"] = 0
