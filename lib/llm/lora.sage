gc_disable()
# LoRA (Low-Rank Adaptation) for efficient fine-tuning
# Adds trainable low-rank matrices to frozen model weights

import math

# ============================================================================
# LoRA adapter
# ============================================================================

# Create a LoRA adapter for a weight matrix
# d_in: input dimension
# d_out: output dimension
# rank: LoRA rank (typically 4-64)
# alpha: scaling factor
proc create_adapter(d_in, d_out, rank, alpha):
    let adapter = {}
    adapter["d_in"] = d_in
    adapter["d_out"] = d_out
    adapter["rank"] = rank
    adapter["alpha"] = alpha
    adapter["scaling"] = alpha / rank
    # A matrix (d_in x rank) - initialized with random normal
    let a = []
    let seed = d_in * 7 + d_out * 13 + rank * 17
    let scale = 1.0 / math.sqrt(rank)
    for i in range(d_in * rank):
        seed = (seed * 1664525 + 1013904223) & 4294967295
        push(a, ((seed & 65535) / 65536 - 0.5) * 2 * scale)
    adapter["A"] = a
    # B matrix (rank x d_out) - initialized to zero
    let b = []
    for i in range(rank * d_out):
        push(b, 0)
    adapter["B"] = b
    adapter["trainable_params"] = d_in * rank + rank * d_out
    return adapter

# Compute LoRA delta: x @ A @ B * scaling
# x: [seq_len * d_in]
proc lora_forward(adapter, x, seq_len):
    let d_in = adapter["d_in"]
    let d_out = adapter["d_out"]
    let rank = adapter["rank"]
    let scaling = adapter["scaling"]
    let a = adapter["A"]
    let b = adapter["B"]
    # x @ A -> [seq_len * rank]
    let hidden = []
    for i in range(seq_len):
        for r in range(rank):
            let s = 0
            for k in range(d_in):
                s = s + x[i * d_in + k] * a[k * rank + r]
            push(hidden, s)
    # hidden @ B -> [seq_len * d_out]
    let delta = []
    for i in range(seq_len):
        for j in range(d_out):
            let s = 0
            for r in range(rank):
                s = s + hidden[i * rank + r] * b[r * d_out + j]
            push(delta, s * scaling)
    return delta

# ============================================================================
# LoRA configuration for a full model
# ============================================================================

proc create_lora_config(rank, alpha, target_modules):
    let cfg = {}
    cfg["rank"] = rank
    cfg["alpha"] = alpha
    cfg["target_modules"] = target_modules
    comptime:
        cfg["dropout"] = 0.0
    return cfg

# Default targets: Q and V projections (most common)
@inline
proc default_targets():
    return ["q_proj", "v_proj"]

# All attention targets
@inline
proc all_attention_targets():
    return ["q_proj", "k_proj", "v_proj", "o_proj"]

# All linear targets (attention + FFN)
@inline
proc all_linear_targets():
    return ["q_proj", "k_proj", "v_proj", "o_proj", "w1", "w2"]

# Apply LoRA adapters to a model's target modules
proc apply_lora(model, lora_cfg):
    let adapters = {}
    let d = model["config"]["d_model"]
    let ff = model["config"]["d_ff"]
    let targets = lora_cfg["target_modules"]
    let rank = lora_cfg["rank"]
    let alpha = lora_cfg["alpha"]
    let total_params = 0
    for layer in range(len(model["blocks"])):
        for t in range(len(targets)):
            let target = targets[t]
            let d_in = d
            let d_out = d
            if target == "w1":
                d_out = ff
            if target == "w2":
                d_in = ff
            let key = str(layer) + "." + target
            adapters[key] = create_adapter(d_in, d_out, rank, alpha)
            total_params = total_params + adapters[key]["trainable_params"]
    let result = {}
    result["adapters"] = adapters
    result["config"] = lora_cfg
    result["total_trainable_params"] = total_params
    result["model_frozen_params"] = 0
    return result

# Get total trainable parameters
@inline
proc trainable_params(lora_result):
    return lora_result["total_trainable_params"]

# Parameter savings ratio
@inline
proc savings_ratio(lora_result, total_model_params):
    return 1.0 - lora_result["total_trainable_params"] / total_model_params

# Merge LoRA weights back into base model (for deployment)
proc merge_weights(base_weight, adapter):
    let d_in = adapter["d_in"]
    let d_out = adapter["d_out"]
    let rank = adapter["rank"]
    let scaling = adapter["scaling"]
    # Compute A @ B
    let delta = []
    for i in range(d_in):
        for j in range(d_out):
            let s = 0
            for r in range(rank):
                s = s + adapter["A"][i * rank + r] * adapter["B"][r * d_out + j]
            push(delta, s * scaling)
    # Add to base weight
    let merged = []
    for i in range(len(base_weight)):
        push(merged, base_weight[i] + delta[i])
    return merged

# ============================================================================
# GPU-accelerated LoRA forward
# ============================================================================

# Accelerated LoRA: x @ A @ B * scaling via gpu_accel matmul
proc lora_forward_accel(ctx, adapter, x, seq_len):
    import ml.gpu_accel
    let d_in = adapter["d_in"]
    let d_out = adapter["d_out"]
    let rank = adapter["rank"]
    let scaling = adapter["scaling"]
    # x @ A: [seq_len x d_in] @ [d_in x rank] -> [seq_len x rank]
    let hidden = gpu_accel.matmul(ctx, x, adapter["A"], seq_len, d_in, rank)
    # hidden @ B: [seq_len x rank] @ [rank x d_out] -> [seq_len x d_out]
    let delta = gpu_accel.matmul(ctx, hidden, adapter["B"], seq_len, rank, d_out)
    # Apply scaling
    return gpu_accel.scale(ctx, delta, scaling)
