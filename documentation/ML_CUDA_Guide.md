# SageLang Machine Learning & CUDA Guide

This guide covers the PyTorch-style machine learning library (`lib/ml/`) and the CUDA GPU abstraction library (`lib/cuda/`).

## Architecture

```text
Application Layer:  Training loops, model definitions
        |
ML Libraries:       lib/ml/tensor, nn, optim, loss, data
        |
CUDA Abstractions:  lib/cuda/device, memory, kernel, stream
        |
GPU Backend:        Sage Vulkan/OpenGL engine (lib/graphics/) or native CUDA
```

The ML libraries are pure Sage and work without GPU hardware. The CUDA libraries provide abstraction layers for GPU programming patterns that can target the Sage Vulkan compute backend or native CUDA.

---

## Tensors (`ml.tensor`)

### Creating Tensors

```sage
import ml.tensor

# From data (auto shape inference)
let t = tensor.tensor([1, 2, 3, 4, 5, 6])
print t["shape"]   # [6]
print t["size"]    # 6

# With explicit shape
let m = tensor.from_flat([1, 2, 3, 4, 5, 6], [2, 3])
print m["shape"]   # [2, 3]

# Factory functions
let z = tensor.zeros([3, 4])        # all zeros
let o = tensor.ones([2, 2])         # all ones
let f = tensor.full([3], 3.14)      # filled with value
let r = tensor.arange(0, 10, 2)     # [0, 2, 4, 6, 8]
let l = tensor.linspace(0, 1, 5)    # [0, 0.25, 0.5, 0.75, 1.0]
let I = tensor.eye(3)               # 3x3 identity
```

### Element-wise Operations

```sage
let a = tensor.tensor([1, 2, 3])
let b = tensor.tensor([4, 5, 6])

let c = tensor.add(a, b)            # [5, 7, 9]
let d = tensor.sub(a, b)            # [-3, -3, -3]
let e = tensor.mul(a, b)            # [4, 10, 18]
let f = tensor.add_scalar(a, 10)    # [11, 12, 13]
let g = tensor.mul_scalar(a, 2)     # [2, 4, 6]
let h = tensor.neg(a)               # [-1, -2, -3]

# Math functions
let ex = tensor.exp_tensor(a)
let lg = tensor.log_tensor(a)
let sq = tensor.sqrt_tensor(a)
let cl = tensor.clamp(a, 0, 2)      # [1, 2, 2]
```

### Reductions

```sage
print tensor.sum_all(a)     # 6
print tensor.mean_all(a)    # 2
print tensor.max_all(a)     # 3
print tensor.min_all(a)     # 1
print tensor.argmax(a)      # 2
print tensor.norm(a)        # sqrt(14)
```

### Matrix Operations

```sage
let A = tensor.from_flat([1, 2, 3, 4], [2, 2])
let B = tensor.from_flat([5, 6, 7, 8], [2, 2])

let C = tensor.matmul(A, B)         # matrix multiply
let At = tensor.transpose(A)        # transpose
let d = tensor.dot(tensor.tensor([1,2]), tensor.tensor([3,4]))  # 11
```

### Activation Functions

```sage
let x = tensor.tensor([-1, 0, 1, 2])
let r = tensor.relu(x)              # [0, 0, 1, 2]
let s = tensor.sigmoid(x)           # [0.27, 0.5, 0.73, 0.88]
let th = tensor.tanh_tensor(x)
let sm = tensor.softmax(x)          # sums to 1.0
```

---

## Neural Networks (`ml.nn`)

### Defining Layers

```sage
import ml.nn

let fc1 = nn.linear(784, 128)       # fully connected
let relu = nn.relu_layer()
let fc2 = nn.linear(128, 10)
let drop = nn.dropout(0.5)          # 50% dropout
let bn = nn.batch_norm(128)         # batch normalization
```

### Sequential Model

```sage
let model = nn.sequential([
    nn.linear(784, 256),
    nn.relu_layer(),
    nn.linear(256, 128),
    nn.relu_layer(),
    nn.linear(128, 10)
])

# Forward pass
let input = tensor.from_flat(input_data, [784])
let output = nn.forward(model, input)
print output["shape"]  # [10]

# Parameter count
print nn.num_parameters(model)

# Train/eval mode
nn.train(model)
nn.eval_mode(model)
```

### Parameters

```sage
let params = nn.parameters(model)
for i in range(len(params)):
    print params[i]["shape"]
```

---

## Optimizers (`ml.optim`)

### SGD

```sage
import ml.optim

let params = nn.parameters(model)
let optimizer = optim.sgd(params, 0.01)

# With momentum
let optimizer = optim.sgd_with_momentum(params, 0.01, 0.9)

# Training step
optim.zero_grad(optimizer)
# ... compute gradients ...
optim.step(optimizer)
```

### Adam

```sage
let optimizer = optim.adam(params, 0.001)
optimizer["beta1"] = 0.9
optimizer["beta2"] = 0.999
optimizer["weight_decay"] = 0.0001

optim.zero_grad(optimizer)
optim.step(optimizer)
```

### Learning Rate Schedulers

```sage
# Step decay: lr *= 0.1 every 30 epochs
optim.step_lr(optimizer, epoch, 30, 0.1)

# Cosine annealing
optim.cosine_lr(optimizer, epoch, 100, 0.0001)

# Warmup
optim.warmup_lr(optimizer, step, 1000, 0.001)
```

---

## Loss Functions (`ml.loss`)

```sage
import ml.loss
import ml.tensor

let pred = tensor.tensor([0.9, 0.1, 0.8])
let target = tensor.tensor([1, 0, 1])

# Mean Squared Error
print loss.mse(pred, target)

# Binary Cross-Entropy
print loss.binary_cross_entropy(pred, target)

# With gradients
let grad = loss.mse_grad(pred, target)

# Other losses
loss.l1(pred, target)                    # Mean Absolute Error
loss.huber(pred, target, 1.0)            # Smooth L1
loss.hinge(pred, target)                 # SVM hinge loss
loss.kl_divergence(p_dist, q_dist)       # KL divergence

# Cross-entropy with logits
let logits = tensor.from_flat([2.0, 1.0, 0.1], [3])
let labels = tensor.from_flat([0], [1])  # class 0
print loss.cross_entropy(logits, labels)
```

---

## Data Loading (`ml.data`)

### Dataset and DataLoader

```sage
import ml.data
import ml.tensor

let features = tensor.from_flat(feature_array, [100, 4])
let labels = tensor.from_flat(label_array, [100])

let dataset = data.create_dataset(features, labels)
print dataset["num_samples"]    # 100
print dataset["feature_dim"]    # 4

# Create batched loader
let loader = data.create_loader(dataset, 32, true)
print loader["num_batches"]     # 4

# Iterate batches
for b in range(loader["num_batches"]):
    let batch = data.get_batch(loader, b)
    let x = batch["features"]   # [batch_size, 4]
    let y = batch["labels"]     # [batch_size]
```

### Preprocessing

```sage
data.normalize(features)          # zero mean, unit variance
data.min_max_scale(features)      # scale to [0, 1]

let encoded = data.one_hot(labels, 10)   # one-hot encode

let split = data.train_test_split(dataset, 0.2)
let train_ds = split["train"]
let test_ds = split["test"]
```

---

## CUDA Device Management (`cuda.device`)

```sage
import cuda.device

# Create a device descriptor
let gpu = device.create_device(0, "RTX 4090", 89, 25769803776)
print device.device_info(gpu)    # "RTX 4090 (SM 8.9, Ada Lovelace, 24576 MB)"

# Feature detection
print device.supports(gpu, "tensor_cores")  # true
print device.supports(gpu, "bf16")          # true
print device.supports(gpu, "fp8")           # true (Ada Lovelace)
print device.supports(gpu, "ray_tracing")   # true

# Device properties
let props = device.device_properties(gpu)
print props["max_threads_per_block"]  # 1024
print props["warp_size"]              # 32
print props["sm_count"]              # 108+

# Launch configuration
let cfg = device.launch_config_1d(1000000, 256)
print cfg["grid"]    # [3907, 1, 1]
print cfg["block"]   # [256, 1, 1]

let cfg2d = device.launch_config_2d(1920, 1080, 16, 16)
```

---

## CUDA Memory (`cuda.memory`)

```sage
import cuda.memory

# Allocate GPU memory
let buf = memory.alloc(4096, memory.MEM_DEVICE)
let tbuf = memory.alloc_typed(1024, "float32")
print tbuf["count"]       # 1024
print tbuf["elem_size"]   # 4

# Tensor allocation
let tmem = memory.alloc_tensor([256, 256], "float32")

# Host-device transfers
memory.copy_h2d(host_data, buf)
let result = memory.copy_d2h(buf)

# Memory pool
let pool = memory.create_pool(1073741824)  # 1 GB
let a = memory.pool_alloc(pool, 4194304)   # 4 MB
let stats = memory.pool_stats(pool)
print memory.format_bytes(stats["used"])
```

---

## CUDA Kernels (`cuda.kernel`)

```sage
import cuda.kernel
import cuda.device

# Define a kernel
let k = kernel.define("saxpy", 256, 0, 12)

# Compute launch parameters
let cfg = kernel.launch_1d(k, 1000000)
print kernel.format_launch(cfg)  # saxpy<<<[3907,1,1], [256,1,1]>>>

# 2D kernel (e.g., image processing)
let k2d = kernel.define("blur", 256, 1024, 16)
let cfg2d = kernel.launch_2d(k2d, 1920, 1080, 16, 16)

# Common kernel patterns
let vadd = kernel.vector_add_kernel(1000000)
let mm = kernel.matmul_kernel(16)      # 16x16 tile shared memory
let red = kernel.reduction_kernel(256)
let conv = kernel.conv2d_kernel(16, 3)

# Occupancy analysis
let dev = device.create_device(0, "A100", 80, 42949672960)
let props = device.device_properties(dev)
let occ = kernel.occupancy(k, props)
print occ["occupancy_pct"]        # percentage
print occ["limiting_factor"]      # "threads", "shared_memory", or "registers"
```

---

## CUDA Streams (`cuda.stream`)

```sage
import cuda.stream

# Create streams
let compute = stream.create_stream(0)
let transfer = stream.create_stream(0)

# Record operations
stream.record_launch(compute, "kernel_a", [100,1,1], [256,1,1])
stream.record_copy(transfer, "host", "device", 4096)

# Events for synchronization
let event = stream.create_event()
stream.record_event(event, transfer)
stream.stream_wait_event(compute, event)

# Multi-stream execution plan
let plan = stream.create_plan()
let cs = stream.add_stream(plan, "compute", 0)
let ts = stream.add_stream(plan, "transfer", 0)

# Double-buffered pipeline
let pipe = stream.double_buffer_plan(4)
let stats = stream.plan_stats(pipe)
print stats["kernel_launches"]
print stats["memory_copies"]
```

---

## Complete Training Example

```sage
import ml.tensor
import ml.nn
import ml.optim
import ml.loss
import ml.data

# Create XOR dataset
let features = tensor.from_flat([0,0, 0,1, 1,0, 1,1], [4, 2])
let labels = tensor.from_flat([0, 1, 1, 0], [4])
let dataset = data.create_dataset(features, labels)

# Build model
let model = nn.sequential([
    nn.linear(2, 8),
    nn.relu_layer(),
    nn.linear(8, 1),
    nn.sigmoid_layer()
])

# Training loop (simplified - no autograd, manual gradient would be needed)
let params = nn.parameters(model)
let optimizer = optim.adam(params, 0.01)

for epoch in range(100):
    let input = dataset["features"]
    let output = nn.forward(model, input)
    let l = loss.mse(output, labels)
    if epoch == 0 or epoch == 99:
        print "Epoch " + str(epoch) + " loss: " + str(l)
    # In a full implementation, backward() would compute gradients
    # optim.step(optimizer)
```

---

## Backpropagation (Native Transformer Training)

SageLang implements explicit backpropagation for a 1-layer SwiGLU transformer, exposed through the `ml_native` C module.

### Forward Pass Architecture

The forward pass follows a standard transformer decoder pipeline:

```text
embed → RMSNorm → Q/K/V projections → causal attention (softmax + mask)
      → O projection → residual → RMSNorm → SwiGLU FFN → residual
      → final norm → LM head
```

- Causal masking ensures each token only attends to prior positions.
- SwiGLU FFN: `gate = silu(x @ gate_w)`, `up = x @ up_w`, `output = (gate * up) @ down_w`.

### Backward Pass

Gradients flow in reverse through each component:

```text
cross-entropy grad → LM head → final norm → FFN (SwiGLU chain rule)
                  → attention O projection → embedding
```

The loss is computed over **all positions** (full-position loss): every token predicts the next, giving denser gradient signal than single-token loss.

### Optimization

- **SGD with gradient clipping**: `max_norm=1.0`; gradients are globally clipped before the weight update step.
- No momentum or adaptive rates in the base implementation — use `optim.adam` from `ml.optim` for adaptive training.

### Training Modes

| Mode             | Entry Point              | Description                                       |
|------------------|--------------------------|---------------------------------------------------|
| Sage interpreter | `ml_native.train_step()` | Full forward + backward + SGD in one native call  |
| C-only binary    | `train_sl_tq`            | Standalone binary; no Sage runtime required       |

```sage
import ml_native

# Single training step (interpreter mode)
let loss = ml_native.train_step(
    embed_w, q_w, k_w, v_w, o_w,
    gate_w, up_w, down_w,
    norm1_w, norm2_w, final_norm_w, lm_head_w,
    input_ids, target_ids,
    seq_len, d_model, d_ff, vocab, lr
)
```

---

## Module Reference

### ML Modules

| Module | Import | Key Functions |
|--------|--------|---------------|
| `tensor` | `import ml.tensor` | `tensor`, `zeros`, `ones`, `eye`, `matmul`, `add`, `mul`, `relu`, `sigmoid`, `softmax`, `reshape`, `transpose` |
| `nn` | `import ml.nn` | `linear`, `relu_layer`, `sigmoid_layer`, `dropout`, `sequential`, `forward`, `parameters`, `num_parameters` |
| `optim` | `import ml.optim` | `sgd`, `adam`, `step`, `zero_grad`, `step_lr`, `cosine_lr`, `warmup_lr` |
| `loss` | `import ml.loss` | `mse`, `cross_entropy`, `binary_cross_entropy`, `huber`, `l1`, `hinge`, `kl_divergence` |
| `data` | `import ml.data` | `create_dataset`, `create_loader`, `get_batch`, `normalize`, `one_hot`, `train_test_split` |

### CUDA Modules

| Module | Import | Key Functions |
|--------|--------|---------------|
| `device` | `import cuda.device` | `create_device`, `device_properties`, `supports`, `launch_config_1d`, `launch_config_2d`, `device_info` |
| `memory` | `import cuda.memory` | `alloc`, `alloc_typed`, `alloc_tensor`, `copy_h2d`, `copy_d2h`, `create_pool`, `pool_alloc`, `format_bytes` |
| `kernel` | `import cuda.kernel` | `define`, `launch_1d`, `launch_2d`, `occupancy`, `vector_add_kernel`, `matmul_kernel`, `format_launch` |
| `stream` | `import cuda.stream` | `create_stream`, `record_launch`, `record_copy`, `create_event`, `record_event`, `create_plan`, `double_buffer_plan` |

### Native Backend Functions (`ml_native`)

These are C-native functions exposed directly to the Sage runtime via the `ml_native` module. They bypass the interpreter for performance-critical operations.

| Function                | Signature                     | Description                                                            |
|-------------------------|-------------------------------|------------------------------------------------------------------------|
| `train_step`            | 19 args (weights, ids, hypers)| Forward pass + backward pass + SGD weight update in a single call      |
| `forward_pass`          | 17 args (weights, ids, hypers)| Inference-only forward pass; output matches training forward exactly   |
| `load_weights`          | `load_weights(path)`          | Native CSV weight parser; loads weights from a file into native arrays |
| `cpu_count`             | `cpu_count()`                 | Returns the number of available logical CPU cores                      |
| `auto_parallel`         | `auto_parallel()`             | Enables all-core parallelism for native matrix operations              |

`train_step` and `forward_pass` share the same weight layout and hyperparameter convention so checkpoints saved during training load directly into inference without conversion.

---

## GPU-Accelerated ML (`ml.gpu_accel`)

The `gpu_accel` module is a unified compute abstraction layer over `ml_native`. It provides GPU-accelerated ML operations with automatic CPU fallback. All operations route through a context that tracks which backend is active.

### Backends

| Backend | Description |
| ------- | ----------- |
| `"gpu"` | Vulkan compute (via Sage graphics engine) |
| `"cpu"` | `ml_native` CPU fallback |
| `"npu"` | NPU (when available) |
| `"tpu"` | TPU (when available) |
| `"auto"` | Auto-detects best available backend |

Override the backend at runtime with the `SAGE_COMPUTE_BACKEND` environment variable:

```sh
SAGE_COMPUTE_BACKEND=cpu ./mymodel
```

> **Note:** Currently GPU dispatch requires the native C module bridge (`ml_gpu`), which is not yet wired. The `gpu_accel` layer routes all operations to `ml_native` (CPU) until the `ml_gpu` native module is built. When compiled with `--compile-llvm`, GPU ops link against `gpu_api.o` + Vulkan/GL libs.

All model files that use GPU acceleration (`build_sagellm`, `train_full`, `sagegpt/model`, `ai_builder`, `inspect_model`) now route through `gpu_accel`.

### Quick Start

```sage
import ml.gpu_accel

# Auto-detect best backend (GPU if available, falls back to CPU)
let ctx = gpu_accel.create("auto")

# All standard ML ops, GPU-aware
let c = gpu_accel.matmul(ctx, a, b, M, K, N)
let normed = gpu_accel.rms_norm(ctx, x, w, seq_len, d_model, 0.00001)
let activated = gpu_accel.silu(ctx, x)
let probs = gpu_accel.softmax(ctx, logits, vocab_size)
let loss = gpu_accel.cross_entropy(ctx, logits, targets, batch, vocab)

print gpu_accel.stats(ctx)  # Shows GPU vs CPU op counts
gpu_accel.destroy(ctx)
```

### High-Level Training Helpers

```sage
import ml.gpu_accel
import llm.attention

let ctx = gpu_accel.create(true)

# Single transformer layer forward pass
let hidden = gpu_accel.transformer_layer_forward(ctx, hidden,
    qw, kw, vw, ow, gate_w, up_w, down_w,
    norm1_w, norm2_w, seq_len, d_model, d_ff,
    attention.scaled_dot_product)

# Full model forward pass (embedding + N layers + LM head)
let logits = gpu_accel.model_forward(ctx, embed_w, layers,
    final_norm_w, lm_head_w, input_ids,
    seq_len, d_model, d_ff, vocab, n_layers,
    attention.scaled_dot_product)

# Training step (forward + cross-entropy loss)
let loss = gpu_accel.train_step(ctx, embed_w, layers,
    final_norm_w, lm_head_w, input_ids, target_ids,
    seq_len, d_model, d_ff, vocab, n_layers,
    attention.scaled_dot_product)
```

### GLSL Compute Shader Templates

The module includes ready-to-use GLSL compute shader source for GPU dispatch:

```sage
# Get GLSL source for GPU matmul
let shader = gpu_accel.matmul_shader_source(M, K, N)

# Other shaders
let soft_shader = gpu_accel.softmax_shader_source()
let silu_shader = gpu_accel.silu_shader_source()
let norm_shader = gpu_accel.rmsnorm_shader_source()
```

### Available Operations

| Function | Description |
|----------|-------------|
| `matmul(ctx, a, b, m, k, n)` | Matrix multiply A[MxK] @ B[KxN] |
| `add(ctx, a, b)` | Element-wise add |
| `scale(ctx, a, s)` | Element-wise scale |
| `rms_norm(ctx, x, w, seq, d, eps)` | RMSNorm |
| `silu(ctx, x)` | SiLU activation |
| `gelu(ctx, x)` | GELU activation |
| `relu(ctx, x)` | ReLU activation |
| `softmax(ctx, x, n)` | Softmax |
| `cross_entropy(ctx, logits, targets, batch, vocab)` | Cross-entropy loss |
| `adam_update(ctx, params, grads, m, v, lr, b1, b2, eps, t)` | Adam optimizer step |
| `clip_grad(ctx, grads, max_norm)` | Gradient clipping |
| `benchmark(ctx, size, iters)` | Performance benchmark |
