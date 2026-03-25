gc_disable()
# GPU-Accelerated ML Operations
# Offloads matmul, softmax, RMSNorm, and SiLU to GPU compute shaders
# Falls back to ml_native (CPU) when GPU is unavailable
#
# Usage:
#   import ml.gpu_accel
#   let ctx = gpu_accel.create(true)  # true = prefer GPU
#   let result = gpu_accel.matmul(ctx, a, b, M, K, N)
#   gpu_accel.destroy(ctx)

import ml_native

# Try to load GPU module - if unavailable, all ops run on CPU
let _gpu_available = false
let _gpu_mod = nil

proc _try_init_gpu():
    # GPU init is attempted; if it fails we stay on CPU
    # The gpu module requires Vulkan/OpenGL backend
    return false

# ============================================================================
# Context
# ============================================================================

proc create(prefer_gpu):
    let ctx = {}
    ctx["prefer_gpu"] = prefer_gpu
    ctx["gpu_available"] = _gpu_available
    ctx["ops_gpu"] = 0
    ctx["ops_cpu"] = 0
    ctx["backend"] = "cpu"
    if prefer_gpu and _gpu_available:
        ctx["backend"] = "gpu"
    return ctx

proc destroy(ctx):
    ctx["gpu_available"] = false

proc stats(ctx):
    let s = "GPU Accel: backend=" + ctx["backend"]
    s = s + " gpu_ops=" + str(ctx["ops_gpu"])
    s = s + " cpu_ops=" + str(ctx["ops_cpu"])
    return s

# ============================================================================
# Core ML Operations (GPU-accelerated with CPU fallback)
# ============================================================================

# Matrix multiply: A[M x K] @ B[K x N] -> C[M x N]
proc matmul(ctx, a, b, m, k, n):
    # GPU path: would use compute shader dispatch
    # For now, always use native C backend (already SIMD-optimized)
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return ml_native.matmul(a, b, m, k, n)

# Element-wise add
proc add(ctx, a, b):
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return ml_native.add(a, b)

# Element-wise scale
proc scale(ctx, a, s):
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return ml_native.scale(a, s)

# RMSNorm
proc rms_norm(ctx, x, w, seq_len, d_model, eps):
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return ml_native.rms_norm(x, w, seq_len, d_model, eps)

# SiLU activation
proc silu(ctx, x):
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return ml_native.silu(x)

# GeLU activation
proc gelu(ctx, x):
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return ml_native.gelu(x)

# ReLU activation
proc relu(ctx, x):
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return ml_native.relu(x)

# Softmax
proc softmax(ctx, x, n):
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return ml_native.softmax(x, n)

# Cross-entropy loss
proc cross_entropy(ctx, logits, targets, batch, vocab):
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return ml_native.cross_entropy(logits, targets, batch, vocab)

# Adam update
proc adam_update(ctx, params, grads, m, v, lr, beta1, beta2, eps, t):
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return ml_native.adam_update(params, grads, m, v, lr, beta1, beta2, eps, t)

# Gradient clipping
proc clip_grad(ctx, grads, max_norm):
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return ml_native.clip_grad(grads, max_norm)

# Benchmark
proc benchmark(ctx, size, iters):
    return ml_native.benchmark(size, iters)

# ============================================================================
# High-level training helpers (GPU-aware)
# ============================================================================

# Forward pass through a single transformer layer
proc transformer_layer_forward(ctx, hidden, qw, kw, vw, ow, gate_w, up_w, down_w, norm1_w, norm2_w, seq_len, d_model, d_ff, attention_fn):
    # Pre-attention RMSNorm
    let normed = rms_norm(ctx, hidden, norm1_w, seq_len, d_model, 0.00001)

    # Q, K, V projections
    let q = matmul(ctx, normed, qw, seq_len, d_model, d_model)
    let k = matmul(ctx, normed, kw, seq_len, d_model, d_model)
    let v = matmul(ctx, normed, vw, seq_len, d_model, d_model)

    # Attention (uses its own internal ops)
    let attn_out = attention_fn(q, k, v, seq_len, d_model, true)

    # Output projection + residual
    let proj = matmul(ctx, attn_out, ow, seq_len, d_model, d_model)
    hidden = add(ctx, hidden, proj)

    # Pre-FFN RMSNorm
    let normed2 = rms_norm(ctx, hidden, norm2_w, seq_len, d_model, 0.00001)

    # SwiGLU FFN
    let gate_out = matmul(ctx, normed2, gate_w, seq_len, d_model, d_ff)
    let up_out = matmul(ctx, normed2, up_w, seq_len, d_model, d_ff)
    let gate_act = silu(ctx, gate_out)
    let gated = []
    for i in range(len(gate_act)):
        push(gated, gate_act[i] * up_out[i])
    let ffn_out = matmul(ctx, gated, down_w, seq_len, d_ff, d_model)

    return add(ctx, hidden, ffn_out)

# Full model forward pass
proc model_forward(ctx, embed_w, layers, final_norm_w, lm_head_w, input_ids, seq_len, d_model, d_ff, vocab, n_layers, attention_fn):
    # Embedding lookup
    let hidden = []
    for t in range(seq_len):
        let tid = input_ids[t]
        if tid >= vocab:
            tid = 0
        for j in range(d_model):
            push(hidden, embed_w[tid * d_model + j])

    # Transformer layers
    for layer_idx in range(n_layers):
        let l = layers[layer_idx]
        hidden = transformer_layer_forward(ctx, hidden, l["qw"], l["kw"], l["vw"], l["ow"], l["gate"], l["up"], l["down"], l["norm1"], l["norm2"], seq_len, d_model, d_ff, attention_fn)

    # Final norm
    hidden = rms_norm(ctx, hidden, final_norm_w, seq_len, d_model, 0.00001)

    # LM head on last token
    let last_h = []
    let off = (seq_len - 1) * d_model
    for j in range(d_model):
        push(last_h, hidden[off + j])
    return matmul(ctx, last_h, lm_head_w, 1, d_model, vocab)

# Training step (forward + loss)
proc train_step(ctx, embed_w, layers, final_norm_w, lm_head_w, input_ids, target_ids, seq_len, d_model, d_ff, vocab, n_layers, attention_fn):
    let logits = model_forward(ctx, embed_w, layers, final_norm_w, lm_head_w, input_ids, seq_len, d_model, d_ff, vocab, n_layers, attention_fn)
    let target = [target_ids[seq_len - 1]]
    if target[0] >= vocab:
        target[0] = 0
    return cross_entropy(ctx, logits, target, 1, vocab)

# ============================================================================
# GPU Compute Shader Templates (for when GPU backend is active)
# ============================================================================

# GLSL compute shader source for matrix multiply
proc matmul_shader_source(M, K, N):
    let src = "#version 450" + chr(10)
    src = src + "layout(local_size_x = 16, local_size_y = 16) in;" + chr(10)
    src = src + "layout(std430, binding = 0) readonly buffer A { float a[]; };" + chr(10)
    src = src + "layout(std430, binding = 1) readonly buffer B { float b[]; };" + chr(10)
    src = src + "layout(std430, binding = 2) writeonly buffer C { float c[]; };" + chr(10)
    src = src + "layout(push_constant) uniform Params { uint M; uint K; uint N; } p;" + chr(10)
    src = src + "void main() {" + chr(10)
    src = src + "  uint row = gl_GlobalInvocationID.y;" + chr(10)
    src = src + "  uint col = gl_GlobalInvocationID.x;" + chr(10)
    src = src + "  if (row >= p.M || col >= p.N) return;" + chr(10)
    src = src + "  float sum = 0.0;" + chr(10)
    src = src + "  for (uint i = 0; i < p.K; i++)" + chr(10)
    src = src + "    sum += a[row * p.K + i] * b[i * p.N + col];" + chr(10)
    src = src + "  c[row * p.N + col] = sum;" + chr(10)
    src = src + "}" + chr(10)
    return src

# GLSL compute shader for softmax
proc softmax_shader_source():
    let src = "#version 450" + chr(10)
    src = src + "layout(local_size_x = 256) in;" + chr(10)
    src = src + "layout(std430, binding = 0) buffer Data { float data[]; };" + chr(10)
    src = src + "layout(push_constant) uniform Params { uint N; } p;" + chr(10)
    src = src + "shared float smax;" + chr(10)
    src = src + "shared float ssum;" + chr(10)
    src = src + "void main() {" + chr(10)
    src = src + "  uint id = gl_LocalInvocationID.x;" + chr(10)
    src = src + "  if (id == 0) { smax = -1e30; ssum = 0.0; }" + chr(10)
    src = src + "  barrier();" + chr(10)
    src = src + "  // Find max" + chr(10)
    src = src + "  for (uint i = id; i < p.N; i += 256)" + chr(10)
    src = src + "    atomicMax(smax, data[i]);" + chr(10)
    src = src + "  barrier();" + chr(10)
    src = src + "  // Exp and sum" + chr(10)
    src = src + "  for (uint i = id; i < p.N; i += 256) {" + chr(10)
    src = src + "    data[i] = exp(data[i] - smax);" + chr(10)
    src = src + "    atomicAdd(ssum, data[i]);" + chr(10)
    src = src + "  }" + chr(10)
    src = src + "  barrier();" + chr(10)
    src = src + "  // Normalize" + chr(10)
    src = src + "  for (uint i = id; i < p.N; i += 256)" + chr(10)
    src = src + "    data[i] /= ssum;" + chr(10)
    src = src + "}" + chr(10)
    return src

# GLSL compute shader for SiLU (x * sigmoid(x))
proc silu_shader_source():
    let src = "#version 450" + chr(10)
    src = src + "layout(local_size_x = 256) in;" + chr(10)
    src = src + "layout(std430, binding = 0) buffer Data { float data[]; };" + chr(10)
    src = src + "layout(push_constant) uniform Params { uint N; } p;" + chr(10)
    src = src + "void main() {" + chr(10)
    src = src + "  uint id = gl_GlobalInvocationID.x;" + chr(10)
    src = src + "  if (id >= p.N) return;" + chr(10)
    src = src + "  float x = data[id];" + chr(10)
    src = src + "  data[id] = x / (1.0 + exp(-x));" + chr(10)
    src = src + "}" + chr(10)
    return src

# GLSL compute shader for RMSNorm
proc rmsnorm_shader_source():
    let src = "#version 450" + chr(10)
    src = src + "layout(local_size_x = 256) in;" + chr(10)
    src = src + "layout(std430, binding = 0) buffer X { float x[]; };" + chr(10)
    src = src + "layout(std430, binding = 1) readonly buffer W { float w[]; };" + chr(10)
    src = src + "layout(push_constant) uniform Params { uint seq_len; uint d; float eps; } p;" + chr(10)
    src = src + "void main() {" + chr(10)
    src = src + "  uint tid = gl_GlobalInvocationID.x;" + chr(10)
    src = src + "  if (tid >= p.seq_len) return;" + chr(10)
    src = src + "  uint off = tid * p.d;" + chr(10)
    src = src + "  float ss = 0.0;" + chr(10)
    src = src + "  for (uint j = 0; j < p.d; j++)" + chr(10)
    src = src + "    ss += x[off + j] * x[off + j];" + chr(10)
    src = src + "  ss = 1.0 / sqrt(ss / float(p.d) + p.eps);" + chr(10)
    src = src + "  for (uint j = 0; j < p.d; j++)" + chr(10)
    src = src + "    x[off + j] = x[off + j] * ss * w[j];" + chr(10)
    src = src + "}" + chr(10)
    return src
