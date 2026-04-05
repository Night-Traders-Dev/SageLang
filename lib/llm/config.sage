gc_disable()
# Model configurations for language models
# Predefined configs from small (GPT-2) to large (Llama-scale)

# ============================================================================
# Configuration builder
# ============================================================================

proc create(name):
    let cfg = {}
    cfg["name"] = name
    comptime:
        cfg["vocab_size"] = 50257
        cfg["context_length"] = 1024
        cfg["n_layers"] = 12
        cfg["n_heads"] = 12
        cfg["d_model"] = 768
        cfg["d_ff"] = 3072
        cfg["dropout"] = 0.1
        cfg["bias"] = true
        cfg["layer_norm_eps"] = 0.00001
        cfg["tie_weights"] = true
        cfg["activation"] = "gelu"
        cfg["pos_encoding"] = "learned"
        cfg["norm_type"] = "layer_norm"
        cfg["attn_type"] = "causal"
        cfg["rope"] = false
        cfg["rope_theta"] = 10000
        cfg["gqa_groups"] = 0
        cfg["sliding_window"] = 0
        cfg["flash_attention"] = false
        cfg["dtype"] = "float32"
    return cfg

# Head dimension
@inline
proc d_head(cfg):
    return (cfg["d_model"] / cfg["n_heads"]) | 0

# Total parameters estimate
proc param_count(cfg):
    let d = cfg["d_model"]
    let ff = cfg["d_ff"]
    let L = cfg["n_layers"]
    let V = cfg["vocab_size"]
    # Embedding: V * d
    let embed = V * d
    # Per transformer layer: attn (4*d*d) + ff (2*d*ff + 2*d) + norms (4*d)
    let attn = 4 * d * d
    let ffn = 2 * d * ff + 2 * d
    let norms = 4 * d
    let per_layer = attn + ffn + norms
    # Output projection (tied = 0, untied = V * d)
    let output = 0
    if not cfg["tie_weights"]:
        output = V * d
    return embed + L * per_layer + output

# Human-readable parameter count
proc param_count_str(cfg):
    let count = param_count(cfg)
    if count >= 1000000000:
        return str((count / 1000000000 * 10) | 0) + "B"
    if count >= 1000000:
        return str((count / 1000000) | 0) + "M"
    if count >= 1000:
        return str((count / 1000) | 0) + "K"
    return str(count)

# Memory estimate in bytes (fp32)
@inline
proc memory_estimate(cfg):
    return param_count(cfg) * 4

# Memory estimate string
proc memory_str(cfg):
    let bytes = memory_estimate(cfg)
    if bytes >= 1073741824:
        return str((bytes / 1073741824 * 10) | 0) + " GB"
    if bytes >= 1048576:
        return str((bytes / 1048576) | 0) + " MB"
    return str((bytes / 1024) | 0) + " KB"

# ============================================================================
# Predefined configurations
# ============================================================================

# Tiny model for testing (~1M params)
proc tiny():
    let cfg = create("sage-tiny")
    cfg["vocab_size"] = 256
    cfg["context_length"] = 128
    cfg["n_layers"] = 2
    cfg["n_heads"] = 2
    cfg["d_model"] = 64
    cfg["d_ff"] = 256
    cfg["dropout"] = 0.0
    return cfg

# Small model (~10M params)
proc small():
    let cfg = create("sage-small")
    cfg["vocab_size"] = 8192
    cfg["context_length"] = 256
    cfg["n_layers"] = 4
    cfg["n_heads"] = 4
    cfg["d_model"] = 128
    cfg["d_ff"] = 512
    cfg["dropout"] = 0.1
    return cfg

# GPT-2 Small (124M params)
proc gpt2():
    let cfg = create("gpt2")
    cfg["vocab_size"] = 50257
    cfg["context_length"] = 1024
    cfg["n_layers"] = 12
    cfg["n_heads"] = 12
    cfg["d_model"] = 768
    cfg["d_ff"] = 3072
    return cfg

# GPT-2 Medium (355M params)
proc gpt2_medium():
    let cfg = create("gpt2-medium")
    cfg["vocab_size"] = 50257
    cfg["context_length"] = 1024
    cfg["n_layers"] = 24
    cfg["n_heads"] = 16
    cfg["d_model"] = 1024
    cfg["d_ff"] = 4096
    return cfg

# GPT-2 Large (774M params)
proc gpt2_large():
    let cfg = create("gpt2-large")
    cfg["vocab_size"] = 50257
    cfg["context_length"] = 1024
    cfg["n_layers"] = 36
    cfg["n_heads"] = 20
    cfg["d_model"] = 1280
    cfg["d_ff"] = 5120
    return cfg

# Llama-style 7B
proc llama_7b():
    let cfg = create("llama-7b")
    cfg["vocab_size"] = 32000
    cfg["context_length"] = 4096
    cfg["n_layers"] = 32
    cfg["n_heads"] = 32
    cfg["d_model"] = 4096
    cfg["d_ff"] = 11008
    cfg["dropout"] = 0.0
    cfg["bias"] = false
    cfg["activation"] = "silu"
    cfg["norm_type"] = "rms_norm"
    cfg["rope"] = true
    cfg["tie_weights"] = false
    return cfg

# Llama-style 13B
proc llama_13b():
    let cfg = create("llama-13b")
    cfg["vocab_size"] = 32000
    cfg["context_length"] = 4096
    cfg["n_layers"] = 40
    cfg["n_heads"] = 40
    cfg["d_model"] = 5120
    cfg["d_ff"] = 13824
    cfg["dropout"] = 0.0
    cfg["bias"] = false
    cfg["activation"] = "silu"
    cfg["norm_type"] = "rms_norm"
    cfg["rope"] = true
    cfg["tie_weights"] = false
    return cfg

# Mistral-style 7B (GQA + sliding window)
proc mistral_7b():
    let cfg = llama_7b()
    cfg["name"] = "mistral-7b"
    cfg["gqa_groups"] = 8
    cfg["sliding_window"] = 4096
    cfg["context_length"] = 32768
    return cfg

# Phi-style small (2.7B)
proc phi_2():
    let cfg = create("phi-2")
    cfg["vocab_size"] = 51200
    cfg["context_length"] = 2048
    cfg["n_layers"] = 32
    cfg["n_heads"] = 32
    cfg["d_model"] = 2560
    cfg["d_ff"] = 10240
    cfg["activation"] = "gelu"
    cfg["rope"] = true
    return cfg

# Agent-optimized small model
proc agent_small():
    let cfg = create("sage-agent-small")
    cfg["vocab_size"] = 32000
    cfg["context_length"] = 4096
    cfg["n_layers"] = 8
    cfg["n_heads"] = 8
    cfg["d_model"] = 512
    cfg["d_ff"] = 2048
    cfg["dropout"] = 0.0
    cfg["activation"] = "silu"
    cfg["norm_type"] = "rms_norm"
    cfg["rope"] = true
    return cfg

# Agent-optimized medium model
proc agent_medium():
    let cfg = create("sage-agent-medium")
    cfg["vocab_size"] = 32000
    cfg["context_length"] = 8192
    cfg["n_layers"] = 16
    cfg["n_heads"] = 16
    cfg["d_model"] = 1024
    cfg["d_ff"] = 4096
    cfg["dropout"] = 0.0
    cfg["activation"] = "silu"
    cfg["norm_type"] = "rms_norm"
    cfg["rope"] = true
    cfg["gqa_groups"] = 4
    return cfg

# Print config summary
proc summary(cfg):
    let nl = chr(10)
    let out = "Model: " + cfg["name"] + nl
    out = out + "Parameters: ~" + param_count_str(cfg) + nl
    out = out + "Memory (fp32): ~" + memory_str(cfg) + nl
    out = out + "Layers: " + str(cfg["n_layers"]) + nl
    out = out + "Heads: " + str(cfg["n_heads"]) + nl
    out = out + "d_model: " + str(cfg["d_model"]) + nl
    out = out + "d_ff: " + str(cfg["d_ff"]) + nl
    out = out + "Context: " + str(cfg["context_length"]) + nl
    out = out + "Vocab: " + str(cfg["vocab_size"]) + nl
    return out
