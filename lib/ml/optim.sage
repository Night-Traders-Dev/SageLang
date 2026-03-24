gc_disable()
# Optimizers for neural network training
# SGD (with momentum), Adam, and learning rate schedulers

import math

# ============================================================================
# SGD Optimizer
# ============================================================================

proc sgd(params, lr):
    let opt = {}
    opt["type"] = "sgd"
    opt["params"] = params
    opt["lr"] = lr
    opt["momentum"] = 0
    opt["weight_decay"] = 0
    # Velocity buffers for momentum
    let velocities = []
    for i in range(len(params)):
        let v = []
        for j in range(params[i]["size"]):
            push(v, 0)
        push(velocities, v)
    opt["velocities"] = velocities
    return opt

proc sgd_with_momentum(params, lr, momentum):
    let opt = sgd(params, lr)
    opt["momentum"] = momentum
    return opt

# SGD step: update parameters using gradients
proc sgd_step(opt):
    let params = opt["params"]
    let lr = opt["lr"]
    let mu = opt["momentum"]
    let wd = opt["weight_decay"]
    for i in range(len(params)):
        let p = params[i]
        if p["grad"] == nil:
            continue
        let g = p["grad"]["data"]
        let d = p["data"]
        let v = opt["velocities"][i]
        for j in range(p["size"]):
            let grad = g[j]
            if wd > 0:
                grad = grad + wd * d[j]
            if mu > 0:
                v[j] = mu * v[j] + grad
                d[j] = d[j] - lr * v[j]
            else:
                d[j] = d[j] - lr * grad

# ============================================================================
# Adam Optimizer
# ============================================================================

proc adam(params, lr):
    let opt = {}
    opt["type"] = "adam"
    opt["params"] = params
    opt["lr"] = lr
    opt["beta1"] = 0.9
    opt["beta2"] = 0.999
    opt["eps"] = 0.00000001
    opt["weight_decay"] = 0
    opt["step_count"] = 0
    # First and second moment buffers
    let m_bufs = []
    let v_bufs = []
    for i in range(len(params)):
        let m = []
        let v = []
        for j in range(params[i]["size"]):
            push(m, 0)
            push(v, 0)
        push(m_bufs, m)
        push(v_bufs, v)
    opt["m"] = m_bufs
    opt["v"] = v_bufs
    return opt

# Adam step
proc adam_step(opt):
    opt["step_count"] = opt["step_count"] + 1
    let t = opt["step_count"]
    let params = opt["params"]
    let lr = opt["lr"]
    let b1 = opt["beta1"]
    let b2 = opt["beta2"]
    let eps = opt["eps"]
    let wd = opt["weight_decay"]
    let bc1 = 1 - math.pow(b1, t)
    let bc2 = 1 - math.pow(b2, t)
    for i in range(len(params)):
        let p = params[i]
        if p["grad"] == nil:
            continue
        let g = p["grad"]["data"]
        let d = p["data"]
        let m = opt["m"][i]
        let v = opt["v"][i]
        for j in range(p["size"]):
            let grad = g[j]
            if wd > 0:
                grad = grad + wd * d[j]
            m[j] = b1 * m[j] + (1 - b1) * grad
            v[j] = b2 * v[j] + (1 - b2) * grad * grad
            let m_hat = m[j] / bc1
            let v_hat = v[j] / bc2
            d[j] = d[j] - lr * m_hat / (math.sqrt(v_hat) + eps)

# ============================================================================
# General step dispatch
# ============================================================================

proc step(opt):
    if opt["type"] == "sgd":
        sgd_step(opt)
    if opt["type"] == "adam":
        adam_step(opt)

# Zero all gradients
proc zero_grad(opt):
    let params = opt["params"]
    for i in range(len(params)):
        if params[i]["grad"] != nil:
            let g = params[i]["grad"]["data"]
            for j in range(len(g)):
                g[j] = 0

# ============================================================================
# Learning rate schedulers
# ============================================================================

# Step decay: multiply lr by gamma every step_size epochs
proc step_lr(opt, epoch, step_size, gamma):
    let factor = math.pow(gamma, (epoch / step_size) | 0)
    opt["lr"] = opt["lr"] * factor

# Exponential decay
proc exp_lr(opt, epoch, gamma):
    opt["lr"] = opt["lr"] * math.pow(gamma, epoch)

# Cosine annealing
proc cosine_lr(opt, epoch, max_epochs, min_lr):
    let base_lr = opt["lr"]
    opt["lr"] = min_lr + (base_lr - min_lr) * 0.5 * (1 + math.cos(math.pi * epoch / max_epochs))

# Warmup: linearly increase lr for first warmup_steps
proc warmup_lr(opt, step_num, warmup_steps, target_lr):
    if step_num < warmup_steps:
        opt["lr"] = target_lr * step_num / warmup_steps
    else:
        opt["lr"] = target_lr
