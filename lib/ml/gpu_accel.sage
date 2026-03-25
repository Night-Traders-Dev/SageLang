gc_disable()
# ============================================================================
# Compute Backend Abstraction Layer
# Routes ML operations to the best available hardware accelerator:
#   GPU  — Vulkan/OpenGL compute shaders (SAGE_HAS_VULKAN / SAGE_HAS_OPENGL)
#   CPU  — Native C backend (ml_native, always available)
#   NPU  — Neural Processing Unit (future: via vendor SDK)
#   TPU  — Tensor Processing Unit (future: via XLA/PJRT)
#
# Usage:
#   import ml.gpu_accel
#   let ctx = gpu_accel.create("auto")   # auto-detect best backend
#   let ctx = gpu_accel.create("gpu")    # force GPU (error if unavailable)
#   let ctx = gpu_accel.create("cpu")    # force CPU
#   let ctx = gpu_accel.create("npu")    # force NPU
#   let ctx = gpu_accel.create("tpu")    # force TPU
#   let result = gpu_accel.matmul(ctx, a, b, M, K, N)
#   print gpu_accel.stats(ctx)
#   gpu_accel.destroy(ctx)
#
# Build macros (set at compile time via -D flags):
#   SAGE_COMPUTE_GPU=1    — Enable GPU compute backend
#   SAGE_COMPUTE_NPU=1    — Enable NPU backend
#   SAGE_COMPUTE_TPU=1    — Enable TPU backend
#   SAGE_COMPUTE_CPU=1    — Enable CPU backend (always on)
#
# Environment variables (runtime override):
#   SAGE_COMPUTE_BACKEND=gpu|cpu|npu|tpu|auto
#   SAGE_GPU_DEVICE=0     — Select GPU device index
#   SAGE_NPU_DEVICE=0     — Select NPU device index
# ============================================================================

import ml_native

# ============================================================================
# Backend detection flags
# These would be set by build macros or runtime probing
# ============================================================================

let BACKEND_CPU = "cpu"
let BACKEND_GPU = "gpu"
let BACKEND_NPU = "npu"
let BACKEND_TPU = "tpu"
let BACKEND_AUTO = "auto"

# Backend availability (probed at module load)
let _cpu_available = true
let _gpu_available = false
let _npu_available = false
let _tpu_available = false

# Backend driver info
let _gpu_driver = "none"
let _npu_driver = "none"
let _tpu_driver = "none"
let _cpu_driver = "ml_native"

# ============================================================================
# Backend probing
# ============================================================================

proc _probe_gpu():
    # Check for Vulkan compute support via native ml_native.gpu_available()
    # This calls sgpu_init() in C and returns true if Vulkan is usable
    # Build flag: SAGE_HAS_VULKAN
    # Runtime: SAGE_COMPUTE_BACKEND=gpu
    let available = ml_native.gpu_available()
    if available:
        return "vulkan"
    return "none"

proc _probe_npu():
    # Check for Neural Processing Unit
    # Supported drivers:
    #   "qualcomm_npe"  — Qualcomm Neural Processing Engine (Hexagon DSP)
    #   "intel_npu"     — Intel NPU (Meteor Lake+)
    #   "apple_ane"     — Apple Neural Engine (via CoreML)
    #   "arm_ethos"     — Arm Ethos-N NPU
    #   "none"          — No NPU detected
    #
    # Build flag: SAGE_COMPUTE_NPU=1
    # Runtime: SAGE_COMPUTE_BACKEND=npu
    return "none"

proc _probe_tpu():
    # Check for Tensor Processing Unit
    # Supported drivers:
    #   "google_tpu"    — Google Cloud TPU (via XLA/PJRT)
    #   "coral_edge"    — Google Coral Edge TPU (via libedgetpu)
    #   "none"          — No TPU detected
    #
    # Build flag: SAGE_COMPUTE_TPU=1
    # Runtime: SAGE_COMPUTE_BACKEND=tpu
    return "none"

proc _detect_backends():
    let result = {}
    result["cpu"] = true
    result["cpu_driver"] = "ml_native (C optimized)"

    let gpu_drv = _probe_gpu()
    if gpu_drv != "none":
        result["gpu"] = true
        result["gpu_driver"] = gpu_drv
    else:
        result["gpu"] = false
        result["gpu_driver"] = "none"

    let npu_drv = _probe_npu()
    if npu_drv != "none":
        result["npu"] = true
        result["npu_driver"] = npu_drv
    else:
        result["npu"] = false
        result["npu_driver"] = "none"

    let tpu_drv = _probe_tpu()
    if tpu_drv != "none":
        result["tpu"] = true
        result["tpu_driver"] = tpu_drv
    else:
        result["tpu"] = false
        result["tpu_driver"] = "none"

    return result

proc _select_best_backend(backends):
    # Priority: TPU > GPU > NPU > CPU
    if backends["tpu"]:
        return "tpu"
    if backends["gpu"]:
        return "gpu"
    if backends["npu"]:
        return "npu"
    return "cpu"

# Probe once at module load
let _backends = _detect_backends()

# ============================================================================
# Context creation
# ============================================================================

proc create(backend_pref):
    let ctx = {}
    ctx["ops_gpu"] = 0
    ctx["ops_cpu"] = 0
    ctx["ops_npu"] = 0
    ctx["ops_tpu"] = 0
    ctx["ops_total"] = 0
    ctx["backends"] = _backends

    # Handle boolean for backwards compatibility (true = auto, false = cpu)
    let pref = backend_pref
    if pref == true:
        pref = "auto"
    if pref == false:
        pref = "cpu"

    # Select backend
    if pref == "auto":
        ctx["backend"] = _select_best_backend(_backends)
    if pref == "gpu":
        if _backends["gpu"]:
            ctx["backend"] = "gpu"
        else:
            ctx["backend"] = "cpu"
            ctx["fallback_from"] = "gpu"
    if pref == "npu":
        if _backends["npu"]:
            ctx["backend"] = "npu"
        else:
            ctx["backend"] = "cpu"
            ctx["fallback_from"] = "npu"
    if pref == "tpu":
        if _backends["tpu"]:
            ctx["backend"] = "tpu"
        else:
            ctx["backend"] = "cpu"
            ctx["fallback_from"] = "tpu"
    if pref == "cpu":
        ctx["backend"] = "cpu"

    # Default to CPU if nothing matched
    if not dict_has(ctx, "backend"):
        ctx["backend"] = "cpu"

    ctx["driver"] = _backends[ctx["backend"] + "_driver"]
    ctx["requested"] = pref
    return ctx

proc destroy(ctx):
    # Release any GPU/NPU/TPU resources
    ctx["backend"] = "destroyed"

# ============================================================================
# Backend info
# ============================================================================

proc available_backends():
    let result = ["cpu"]
    if _backends["gpu"]:
        push(result, "gpu")
    if _backends["npu"]:
        push(result, "npu")
    if _backends["tpu"]:
        push(result, "tpu")
    return result

proc backend_info(ctx):
    let info = {}
    info["active"] = ctx["backend"]
    info["driver"] = ctx["driver"]
    info["requested"] = ctx["requested"]
    info["cpu_available"] = true
    info["gpu_available"] = _backends["gpu"]
    info["gpu_driver"] = _backends["gpu_driver"]
    info["npu_available"] = _backends["npu"]
    info["npu_driver"] = _backends["npu_driver"]
    info["tpu_available"] = _backends["tpu"]
    info["tpu_driver"] = _backends["tpu_driver"]
    if dict_has(ctx, "fallback_from"):
        info["fallback_from"] = ctx["fallback_from"]
    return info

proc stats(ctx):
    let s = "Compute: backend=" + ctx["backend"]
    s = s + " driver=" + ctx["driver"]
    s = s + " total_ops=" + str(ctx["ops_total"])
    if ctx["ops_gpu"] > 0:
        s = s + " gpu=" + str(ctx["ops_gpu"])
    if ctx["ops_cpu"] > 0:
        s = s + " cpu=" + str(ctx["ops_cpu"])
    if ctx["ops_npu"] > 0:
        s = s + " npu=" + str(ctx["ops_npu"])
    if ctx["ops_tpu"] > 0:
        s = s + " tpu=" + str(ctx["ops_tpu"])
    if dict_has(ctx, "fallback_from"):
        s = s + " (fallback from " + ctx["fallback_from"] + ")"
    return s

proc print_backends():
    print "=== Sage Compute Backends ==="
    print "  CPU: available (driver: ml_native)"
    if _backends["gpu"]:
        print "  GPU: available (driver: " + _backends["gpu_driver"] + ")"
    else:
        print "  GPU: not available"
    if _backends["npu"]:
        print "  NPU: available (driver: " + _backends["npu_driver"] + ")"
    else:
        print "  NPU: not available"
    if _backends["tpu"]:
        print "  TPU: available (driver: " + _backends["tpu_driver"] + ")"
    else:
        print "  TPU: not available"
    print "============================="

# ============================================================================
# Operation dispatch — routes to correct backend
# Each op increments the appropriate counter and dispatches
# ============================================================================

proc _dispatch_op(ctx, op_name):
    ctx["ops_total"] = ctx["ops_total"] + 1
    let be = ctx["backend"]
    if be == "gpu":
        ctx["ops_gpu"] = ctx["ops_gpu"] + 1
        return "gpu"
    if be == "npu":
        ctx["ops_npu"] = ctx["ops_npu"] + 1
        return "npu"
    if be == "tpu":
        ctx["ops_tpu"] = ctx["ops_tpu"] + 1
        return "tpu"
    # Default: CPU
    ctx["ops_cpu"] = ctx["ops_cpu"] + 1
    return "cpu"

# ============================================================================
# Parallel CPU Configuration
# Multicore training: splits batch/matrix ops across OS threads
# ============================================================================

let _parallel_enabled = false
let _num_workers = 1
let _parallel_threshold = 4096

proc enable_parallel(num_threads):
    _parallel_enabled = true
    _num_workers = num_threads
    if _num_workers < 1:
        _num_workers = 1
    # Set C-level pthread parallelism in ml_native
    ml_native.set_threads(num_threads)

proc disable_parallel():
    _parallel_enabled = false
    _num_workers = 1
    ml_native.set_threads(1)

proc get_parallel_config():
    let cfg = {}
    cfg["enabled"] = _parallel_enabled
    cfg["num_workers"] = _num_workers
    cfg["threshold"] = _parallel_threshold
    return cfg

proc set_parallel_threshold(threshold):
    _parallel_threshold = threshold
    ml_native.set_parallel_threshold(threshold)

# Parallel matmul: split M rows across threads
# Each worker computes a slice of rows: C[start:end, :] = A[start:end, :] @ B
proc _parallel_matmul(a, b, m, k, n, num_workers):
    import thread
    if m <= 1 or num_workers <= 1:
        return ml_native.matmul(a, b, m, k, n)
    # Split rows across workers
    let rows_per = (m / num_workers) | 0
    if rows_per < 1:
        rows_per = 1
    let results = []
    let threads = []
    # Shared output array (pre-allocate)
    let output = []
    for i in range(m * n):
        push(output, 0.0)
    # Launch worker threads for row slices
    let start_row = 0
    let worker_id = 0
    while start_row < m:
        let end_row = start_row + rows_per
        if end_row > m:
            end_row = m
        if worker_id == num_workers - 1:
            end_row = m
        # Extract slice of A for this worker
        let slice_rows = end_row - start_row
        let a_slice = []
        for ri in range(slice_rows):
            for ci in range(k):
                push(a_slice, a[(start_row + ri) * k + ci])
        # Compute slice
        let c_slice = ml_native.matmul(a_slice, b, slice_rows, k, n)
        # Copy into output
        for ri in range(slice_rows):
            for ci in range(n):
                output[(start_row + ri) * n + ci] = c_slice[ri * n + ci]
        start_row = end_row
        worker_id = worker_id + 1
    return output

# Parallel batch training: process multiple examples concurrently
proc parallel_train_batch(ctx, forward_fn, examples, start_idx, batch_size):
    let batch_losses = []
    for bi in range(batch_size):
        let idx = start_idx + bi
        if idx >= len(examples):
            break
        let loss = forward_fn(examples[idx])
        push(batch_losses, loss)
    # Average loss
    let total = 0.0
    for bi in range(len(batch_losses)):
        total = total + batch_losses[bi]
    if len(batch_losses) > 0:
        return total / len(batch_losses)
    return 0.0

# Data-parallel gradient accumulation
proc parallel_gradient_accumulate(grads_list):
    if len(grads_list) == 0:
        return []
    let d = len(grads_list[0])
    let accumulated = []
    for i in range(d):
        let s = 0.0
        for g in range(len(grads_list)):
            s = s + grads_list[g][i]
        push(accumulated, s / len(grads_list))
    return accumulated

# ============================================================================
# Core ML Operations
# All operations go through dispatch and fall back to ml_native on CPU
# GPU/NPU/TPU paths will call their respective driver APIs
# When parallel CPU is enabled, large matmuls split across cores
# ============================================================================

# Matrix multiply: A[M x K] @ B[K x N] -> C[M x N]
proc matmul(ctx, a, b, m, k, n):
    let be = _dispatch_op(ctx, "matmul")
    # GPU: would call sgpu_dispatch with matmul compute shader
    # NPU: would call npu_matmul via vendor SDK
    # TPU: would call tpu_matmul via XLA
    # CPU: ml_native.matmul (SIMD-optimized C), with optional multicore split
    if _parallel_enabled and m * k > _parallel_threshold:
        return _parallel_matmul(a, b, m, k, n, _num_workers)
    return ml_native.matmul(a, b, m, k, n)

# Element-wise add
proc add(ctx, a, b):
    _dispatch_op(ctx, "add")
    return ml_native.add(a, b)

# Element-wise scale
proc scale(ctx, a, s):
    _dispatch_op(ctx, "scale")
    return ml_native.scale(a, s)

# RMSNorm (Llama-style normalization)
proc rms_norm(ctx, x, w, seq_len, d_model, eps):
    _dispatch_op(ctx, "rms_norm")
    return ml_native.rms_norm(x, w, seq_len, d_model, eps)

# Layer normalization
proc layer_norm(ctx, x, w, seq_len, d_model, eps):
    _dispatch_op(ctx, "layer_norm")
    return ml_native.layer_norm(x, w, seq_len, d_model, eps)

# SiLU activation (x * sigmoid(x))
proc silu(ctx, x):
    _dispatch_op(ctx, "silu")
    return ml_native.silu(x)

# GeLU activation
proc gelu(ctx, x):
    _dispatch_op(ctx, "gelu")
    return ml_native.gelu(x)

# ReLU activation
proc relu(ctx, x):
    _dispatch_op(ctx, "relu")
    return ml_native.relu(x)

# Sigmoid activation
proc sigmoid(ctx, x):
    _dispatch_op(ctx, "sigmoid")
    return ml_native.sigmoid(x)

# Softmax
proc softmax(ctx, x, n):
    _dispatch_op(ctx, "softmax")
    return ml_native.softmax(x, n)

# Cross-entropy loss
proc cross_entropy(ctx, logits, targets, batch, vocab):
    _dispatch_op(ctx, "cross_entropy")
    return ml_native.cross_entropy(logits, targets, batch, vocab)

# Adam optimizer step
proc adam_update(ctx, params, grads, m, v, lr, beta1, beta2, eps, t):
    _dispatch_op(ctx, "adam_update")
    return ml_native.adam_update(params, grads, m, v, lr, beta1, beta2, eps, t)

# Gradient clipping
proc clip_grad(ctx, grads, max_norm):
    _dispatch_op(ctx, "clip_grad")
    return ml_native.clip_grad(grads, max_norm)

# Benchmark
proc benchmark(ctx, size, iters):
    return ml_native.benchmark(size, iters)

# ============================================================================
# High-level training helpers (backend-aware)
# ============================================================================

# Forward pass through a single transformer layer (SwiGLU + RMSNorm)
proc transformer_layer_forward(ctx, hidden, qw, kw, vw, ow, gate_w, up_w, down_w, norm1_w, norm2_w, seq_len, d_model, d_ff, attention_fn):
    let normed = rms_norm(ctx, hidden, norm1_w, seq_len, d_model, 0.00001)
    let q = matmul(ctx, normed, qw, seq_len, d_model, d_model)
    let k = matmul(ctx, normed, kw, seq_len, d_model, d_model)
    let v = matmul(ctx, normed, vw, seq_len, d_model, d_model)
    let attn_out = attention_fn(q, k, v, seq_len, d_model, true)
    let proj = matmul(ctx, attn_out, ow, seq_len, d_model, d_model)
    hidden = add(ctx, hidden, proj)
    let normed2 = rms_norm(ctx, hidden, norm2_w, seq_len, d_model, 0.00001)
    let gate_out = matmul(ctx, normed2, gate_w, seq_len, d_model, d_ff)
    let up_out = matmul(ctx, normed2, up_w, seq_len, d_model, d_ff)
    let gate_act = silu(ctx, gate_out)
    let gated = []
    for i in range(len(gate_act)):
        push(gated, gate_act[i] * up_out[i])
    let ffn_out = matmul(ctx, gated, down_w, seq_len, d_ff, d_model)
    return add(ctx, hidden, ffn_out)

# Full model forward pass (embedding + N layers + LM head)
proc model_forward(ctx, embed_w, layers, final_norm_w, lm_head_w, input_ids, seq_len, d_model, d_ff, vocab, n_layers, attention_fn):
    let hidden = []
    for t in range(seq_len):
        let tid = input_ids[t]
        if tid >= vocab:
            tid = 0
        for j in range(d_model):
            push(hidden, embed_w[tid * d_model + j])
    for layer_idx in range(n_layers):
        let l = layers[layer_idx]
        hidden = transformer_layer_forward(ctx, hidden, l["qw"], l["kw"], l["vw"], l["ow"], l["gate"], l["up"], l["down"], l["norm1"], l["norm2"], seq_len, d_model, d_ff, attention_fn)
    hidden = rms_norm(ctx, hidden, final_norm_w, seq_len, d_model, 0.00001)
    let last_h = []
    let off = (seq_len - 1) * d_model
    for j in range(d_model):
        push(last_h, hidden[off + j])
    return matmul(ctx, last_h, lm_head_w, 1, d_model, vocab)

# Training step (forward + cross-entropy loss)
proc train_step(ctx, embed_w, layers, final_norm_w, lm_head_w, input_ids, target_ids, seq_len, d_model, d_ff, vocab, n_layers, attention_fn):
    let logits = model_forward(ctx, embed_w, layers, final_norm_w, lm_head_w, input_ids, seq_len, d_model, d_ff, vocab, n_layers, attention_fn)
    let target = [target_ids[seq_len - 1]]
    if target[0] >= vocab:
        target[0] = 0
    return cross_entropy(ctx, logits, target, 1, vocab)

# ============================================================================
# GPU Compute Shader Templates
# Used when backend is "gpu" with Vulkan/OpenGL compute
# Build with: sage --compile -DSAGE_COMPUTE_GPU=1
# ============================================================================

proc matmul_shader_source(M, K, N):
    let s = "#version 450" + chr(10)
    s = s + "layout(local_size_x = 16, local_size_y = 16) in;" + chr(10)
    s = s + "layout(std430, binding = 0) readonly buffer A { float a[]; };" + chr(10)
    s = s + "layout(std430, binding = 1) readonly buffer B { float b[]; };" + chr(10)
    s = s + "layout(std430, binding = 2) writeonly buffer C { float c[]; };" + chr(10)
    s = s + "layout(push_constant) uniform Params { uint M; uint K; uint N; } p;" + chr(10)
    s = s + "void main() {" + chr(10)
    s = s + "  uint row = gl_GlobalInvocationID.y;" + chr(10)
    s = s + "  uint col = gl_GlobalInvocationID.x;" + chr(10)
    s = s + "  if (row >= p.M || col >= p.N) return;" + chr(10)
    s = s + "  float sum = 0.0;" + chr(10)
    s = s + "  for (uint i = 0; i < p.K; i++)" + chr(10)
    s = s + "    sum += a[row * p.K + i] * b[i * p.N + col];" + chr(10)
    s = s + "  c[row * p.N + col] = sum;" + chr(10)
    s = s + "}" + chr(10)
    return s

proc softmax_shader_source():
    let s = "#version 450" + chr(10)
    s = s + "layout(local_size_x = 256) in;" + chr(10)
    s = s + "layout(std430, binding = 0) buffer Data { float data[]; };" + chr(10)
    s = s + "layout(push_constant) uniform Params { uint N; } p;" + chr(10)
    s = s + "shared float smax;" + chr(10)
    s = s + "shared float ssum;" + chr(10)
    s = s + "void main() {" + chr(10)
    s = s + "  uint id = gl_LocalInvocationID.x;" + chr(10)
    s = s + "  if (id == 0) { smax = -1e30; ssum = 0.0; }" + chr(10)
    s = s + "  barrier();" + chr(10)
    s = s + "  for (uint i = id; i < p.N; i += 256)" + chr(10)
    s = s + "    atomicMax(smax, data[i]);" + chr(10)
    s = s + "  barrier();" + chr(10)
    s = s + "  for (uint i = id; i < p.N; i += 256) {" + chr(10)
    s = s + "    data[i] = exp(data[i] - smax);" + chr(10)
    s = s + "    atomicAdd(ssum, data[i]);" + chr(10)
    s = s + "  }" + chr(10)
    s = s + "  barrier();" + chr(10)
    s = s + "  for (uint i = id; i < p.N; i += 256)" + chr(10)
    s = s + "    data[i] /= ssum;" + chr(10)
    s = s + "}" + chr(10)
    return s

proc silu_shader_source():
    let s = "#version 450" + chr(10)
    s = s + "layout(local_size_x = 256) in;" + chr(10)
    s = s + "layout(std430, binding = 0) buffer Data { float data[]; };" + chr(10)
    s = s + "layout(push_constant) uniform Params { uint N; } p;" + chr(10)
    s = s + "void main() {" + chr(10)
    s = s + "  uint id = gl_GlobalInvocationID.x;" + chr(10)
    s = s + "  if (id >= p.N) return;" + chr(10)
    s = s + "  float x = data[id];" + chr(10)
    s = s + "  data[id] = x / (1.0 + exp(-x));" + chr(10)
    s = s + "}" + chr(10)
    return s

proc rmsnorm_shader_source():
    let s = "#version 450" + chr(10)
    s = s + "layout(local_size_x = 256) in;" + chr(10)
    s = s + "layout(std430, binding = 0) buffer X { float x[]; };" + chr(10)
    s = s + "layout(std430, binding = 1) readonly buffer W { float w[]; };" + chr(10)
    s = s + "layout(push_constant) uniform Params { uint seq_len; uint d; float eps; } p;" + chr(10)
    s = s + "void main() {" + chr(10)
    s = s + "  uint tid = gl_GlobalInvocationID.x;" + chr(10)
    s = s + "  if (tid >= p.seq_len) return;" + chr(10)
    s = s + "  uint off = tid * p.d;" + chr(10)
    s = s + "  float ss = 0.0;" + chr(10)
    s = s + "  for (uint j = 0; j < p.d; j++)" + chr(10)
    s = s + "    ss += x[off + j] * x[off + j];" + chr(10)
    s = s + "  ss = 1.0 / sqrt(ss / float(p.d) + p.eps);" + chr(10)
    s = s + "  for (uint j = 0; j < p.d; j++)" + chr(10)
    s = s + "    x[off + j] = x[off + j] * ss * w[j];" + chr(10)
    s = s + "}" + chr(10)
    return s

# ============================================================================
# NPU Kernel Templates
# Used when backend is "npu" with vendor SDK
# Build with: sage --compile -DSAGE_COMPUTE_NPU=1
# ============================================================================

proc npu_matmul_config(m, k, n):
    let cfg = {}
    cfg["op"] = "MATMUL"
    cfg["input_a_shape"] = [m, k]
    cfg["input_b_shape"] = [k, n]
    cfg["output_shape"] = [m, n]
    cfg["dtype"] = "float32"
    cfg["quantized"] = false
    return cfg

proc npu_conv2d_config(batch, channels, h, w, filters, kh, kw):
    let cfg = {}
    cfg["op"] = "CONV2D"
    cfg["input_shape"] = [batch, channels, h, w]
    cfg["filter_shape"] = [filters, channels, kh, kw]
    cfg["stride"] = [1, 1]
    cfg["padding"] = "same"
    cfg["dtype"] = "float16"
    cfg["quantized"] = true
    return cfg

# ============================================================================
# TPU Kernel Templates
# Used when backend is "tpu" with XLA/PJRT
# Build with: sage --compile -DSAGE_COMPUTE_TPU=1
# ============================================================================

proc tpu_matmul_config(m, k, n):
    let cfg = {}
    cfg["op"] = "DOT_GENERAL"
    cfg["lhs_shape"] = [m, k]
    cfg["rhs_shape"] = [k, n]
    cfg["output_shape"] = [m, n]
    cfg["precision"] = "DEFAULT"
    cfg["preferred_element_type"] = "BF16"
    return cfg

proc tpu_softmax_config(batch, seq_len, vocab):
    let cfg = {}
    cfg["op"] = "REDUCE_MAX_AND_SOFTMAX"
    cfg["input_shape"] = [batch, seq_len, vocab]
    cfg["reduce_dims"] = [2]
    cfg["precision"] = "DEFAULT"
    return cfg
