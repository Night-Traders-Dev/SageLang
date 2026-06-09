gc_disable()
# Transformer blocks and full model assembly
# Supports GPT-style decoder-only architecture
#
# GPU acceleration: use apply_rms_norm_accel() and ffn_forward_accel()
# with a gpu_accel context for GPU/NPU/TPU offload.
# Standard functions always run on CPU (pure Sage).

import math

# ============================================================================
# Layer Normalization
# ============================================================================

proc create_layer_norm(d_model, eps):
    let ln = {}
    ln["d_model"] = d_model
    ln["eps"] = eps
    let gamma = []
    let beta = []
    for i in range(d_model):
        push(gamma, 1.0)
        push(beta, 0.0)
    ln["gamma"] = gamma
    ln["beta"] = beta
    return ln

# Apply layer norm to one vector of size d_model
proc layer_norm(ln, x, offset, d):
    # Compute mean
    let mu = 0
    for i in range(d):
        mu = mu + x[offset + i]
    mu = mu / d
    # Compute variance
    let var_sum = 0
    for i in range(d):
        let diff = x[offset + i] - mu
        var_sum = var_sum + diff * diff
    var_sum = var_sum / d
    let std = math.sqrt(var_sum + ln["eps"])
    let result = []
    for i in range(d):
        push(result, ln["gamma"][i] * (x[offset + i] - mu) / std + ln["beta"][i])
    return result

# Apply layer norm to full sequence [seq_len * d_model]
proc apply_layer_norm(ln, x, seq_len):
    let d = ln["d_model"]
    let result = []
    for i in range(seq_len):
        let normed = layer_norm(ln, x, i * d, d)
        for j in range(d):
            push(result, normed[j])
    return result

# ============================================================================
# RMS Normalization (Llama-style)
# ============================================================================

proc create_rms_norm(d_model, eps):
    let rn = {}
    rn["d_model"] = d_model
    rn["eps"] = eps
    let weight = []
    for i in range(d_model):
        push(weight, 1.0)
    rn["weight"] = weight
    return rn

proc apply_rms_norm(rn, x, seq_len):
    let d = rn["d_model"]
    let result = []
    for i in range(seq_len):
        let ss = 0
        for j in range(d):
            let v = x[i * d + j]
            ss = ss + v * v
        let rms = math.sqrt(ss / d + rn["eps"])
        for j in range(d):
            push(result, x[i * d + j] / rms * rn["weight"][j])
    return result

# ============================================================================
# Feed-Forward Network (MLP)
# ============================================================================

proc create_ffn(d_model, d_ff, activation):
    let ffn = {}
    ffn["d_model"] = d_model
    ffn["d_ff"] = d_ff
    ffn["activation"] = activation
    # Up projection
    let scale = 1.0 / math.sqrt(d_model)
    let w1 = []
    let seed = d_model * 23 + d_ff * 37
    for i in range(d_model * d_ff):
        seed = (seed * 1664525 + 1013904223) & 4294967295
        push(w1, ((seed & 65535) / 65536 - 0.5) * 2 * scale)
    ffn["w1"] = w1
    # Down projection
    let w2 = []
    let scale2 = 1.0 / math.sqrt(d_ff)
    for i in range(d_ff * d_model):
        seed = (seed * 1664525 + 1013904223) & 4294967295
        push(w2, ((seed & 65535) / 65536 - 0.5) * 2 * scale2)
    ffn["w2"] = w2
    let b1 = []
    let b2 = []
    for i in range(d_ff):
        push(b1, 0)
    for i in range(d_model):
        push(b2, 0)
    ffn["b1"] = b1
    ffn["b2"] = b2
    return ffn

# Activation functions
@inline
proc gelu(x):
    return 0.5 * x * (1.0 + math.tanh(math.sqrt(2.0 / math.pi) * (x + 0.044715 * x * x * x)))

@inline
proc silu(x):
    return x / (1.0 + math.exp(0 - x))

proc apply_activation(name, x):
    if name == "relu":
        if x > 0:
            return x
        return 0
    if name == "gelu":
        return gelu(x)
    if name == "silu":
        return silu(x)
    return x

# FFN forward: x -> up_proj -> activation -> down_proj
proc ffn_forward(ffn, x, seq_len):
    let d = ffn["d_model"]
    let ff = ffn["d_ff"]
    let act = ffn["activation"]
    let result = []
    for i in range(seq_len):
        # Up projection
        let hidden = []
        for j in range(ff):
            let s = ffn["b1"][j]
            for k in range(d):
                s = s + x[i * d + k] * ffn["w1"][j * d + k]
            push(hidden, apply_activation(act, s))
        # Down projection
        for j in range(d):
            let s = ffn["b2"][j]
            for k in range(ff):
                s = s + hidden[k] * ffn["w2"][j * ff + k]
            push(result, s)
    return result

# ============================================================================
# Transformer Block
# ============================================================================

proc create_block(cfg):
    let block = {}
    block["d_model"] = cfg["d_model"]
    # Attention
    let mha = {}
    mha["d_model"] = cfg["d_model"]
    mha["n_heads"] = cfg["n_heads"]
    mha["d_head"] = (cfg["d_model"] / cfg["n_heads"]) | 0
    block["attention"] = mha
    # Feed-forward
    block["ffn"] = create_ffn(cfg["d_model"], cfg["d_ff"], cfg["activation"])
    # Norms
    let eps = cfg["layer_norm_eps"]
    if cfg["norm_type"] == "rms_norm":
        block["norm1"] = create_rms_norm(cfg["d_model"], eps)
        block["norm2"] = create_rms_norm(cfg["d_model"], eps)
        block["norm_type"] = "rms_norm"
    else:
        block["norm1"] = create_layer_norm(cfg["d_model"], eps)
        block["norm2"] = create_layer_norm(cfg["d_model"], eps)
        block["norm_type"] = "layer_norm"
    return block

# ============================================================================
# Full Transformer Model
# ============================================================================

proc create_model(cfg):
    let model = {}
    model["config"] = cfg
    model["blocks"] = []
    for i in range(cfg["n_layers"]):
        push(model["blocks"], create_block(cfg))
    # Final norm
    if cfg["norm_type"] == "rms_norm":
        model["final_norm"] = create_rms_norm(cfg["d_model"], cfg["layer_norm_eps"])
    else:
        model["final_norm"] = create_layer_norm(cfg["d_model"], cfg["layer_norm_eps"])
    model["final_norm_type"] = cfg["norm_type"]
    return model

# Count parameters
proc model_param_count(model):
    let cfg = model["config"]
    let d = cfg["d_model"]
    let ff = cfg["d_ff"]
    let L = cfg["n_layers"]
    let V = cfg["vocab_size"]
    return V * d + L * (4 * d * d + 2 * d * ff + 6 * d) + d

# ============================================================================
# Residual connection
# ============================================================================

proc residual_add(x, residual, length):
    let result = []
    for i in range(length):
        push(result, x[i] + residual[i])
    return result

# ============================================================================
# GPU-accelerated variants
# These route compute through a gpu_accel context for GPU/NPU/TPU offload
# ============================================================================

# Accelerated RMSNorm via gpu_accel backend
proc apply_rms_norm_accel(ctx, rn, x, seq_len):
    import ml.gpu_accel
    return gpu_accel.rms_norm(ctx, x, rn["weight"], seq_len, rn["d_model"], rn["eps"])

# Accelerated FFN forward via gpu_accel backend
proc ffn_forward_accel(ctx, ffn, x, seq_len):
    import ml.gpu_accel
    let d = ffn["d_model"]
    let ff = ffn["d_ff"]
    # x @ W1: [seq_len x d] @ [d x ff] -> [seq_len x ff]
    let h = gpu_accel.matmul(ctx, x, ffn["w1"], seq_len, d, ff)
    # Activation
    let act = ffn["activation"]
    if act == "silu":
        h = gpu_accel.silu(ctx, h)
    if act == "gelu":
        h = gpu_accel.gelu(ctx, h)
    if act == "relu":
        h = gpu_accel.relu(ctx, h)
    # h @ W2: [seq_len x ff] @ [ff x d] -> [seq_len x d]
    return gpu_accel.matmul(ctx, h, ffn["w2"], seq_len, ff, d)

# Accelerated residual add
proc residual_add_accel(ctx, x, residual):
    import ml.gpu_accel
    return gpu_accel.add(ctx, x, residual)
