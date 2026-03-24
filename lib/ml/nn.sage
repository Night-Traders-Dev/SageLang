# Neural network layers and model building blocks
# PyTorch-style API: Linear, Conv (1D), ReLU, Sigmoid, Sequential, Dropout

# ============================================================================
# Layer: Linear (fully connected)
# ============================================================================

proc linear(in_features, out_features):
    let layer = {}
    layer["type"] = "linear"
    layer["in_features"] = in_features
    layer["out_features"] = out_features
    # Xavier initialization
    let scale = 1.0 / in_features
    let w_data = []
    let b_data = []
    let seed = in_features * 7 + out_features * 13 + 42
    for i in range(in_features * out_features):
        seed = (seed * 1664525 + 1013904223) & 4294967295
        let val = ((seed & 65535) / 65536 - 0.5) * 2 * scale
        push(w_data, val)
    for i in range(out_features):
        push(b_data, 0)
    layer["weight"] = {}
    layer["weight"]["data"] = w_data
    layer["weight"]["shape"] = [out_features, in_features]
    layer["weight"]["size"] = in_features * out_features
    layer["weight"]["ndim"] = 2
    layer["weight"]["requires_grad"] = true
    layer["weight"]["grad"] = nil
    layer["bias"] = {}
    layer["bias"]["data"] = b_data
    layer["bias"]["shape"] = [out_features]
    layer["bias"]["size"] = out_features
    layer["bias"]["ndim"] = 1
    layer["bias"]["requires_grad"] = true
    layer["bias"]["grad"] = nil
    return layer

# Forward pass for linear layer: y = x @ W^T + b
proc linear_forward(layer, x):
    let in_f = layer["in_features"]
    let out_f = layer["out_features"]
    let w = layer["weight"]["data"]
    let b = layer["bias"]["data"]
    let x_data = x["data"]
    # Handle batched input [batch, in_features]
    let batch = 1
    if x["ndim"] == 2:
        batch = x["shape"][0]
    let result = []
    for i in range(batch):
        for j in range(out_f):
            let s = b[j]
            for k in range(in_f):
                s = s + x_data[i * in_f + k] * w[j * in_f + k]
            push(result, s)
    if batch == 1:
        let out = {}
        out["data"] = result
        out["shape"] = [out_f]
        out["size"] = out_f
        out["ndim"] = 1
        out["requires_grad"] = false
        out["grad"] = nil
        out["_grad_fn"] = nil
        return out
    let out = {}
    out["data"] = result
    out["shape"] = [batch, out_f]
    out["size"] = batch * out_f
    out["ndim"] = 2
    out["requires_grad"] = false
    out["grad"] = nil
    out["_grad_fn"] = nil
    return out

# ============================================================================
# Activation layers
# ============================================================================

proc relu_layer():
    let layer = {}
    layer["type"] = "relu"
    return layer

proc sigmoid_layer():
    let layer = {}
    layer["type"] = "sigmoid"
    return layer

proc tanh_layer():
    let layer = {}
    layer["type"] = "tanh"
    return layer

proc relu_forward(x):
    let data = []
    for i in range(x["size"]):
        let v = x["data"][i]
        if v > 0:
            push(data, v)
        else:
            push(data, 0)
    let out = {}
    out["data"] = data
    out["shape"] = x["shape"]
    out["size"] = x["size"]
    out["ndim"] = x["ndim"]
    out["requires_grad"] = false
    out["grad"] = nil
    out["_grad_fn"] = nil
    return out

proc sigmoid_forward(x):
    import math
    let data = []
    for i in range(x["size"]):
        push(data, 1 / (1 + math.exp(0 - x["data"][i])))
    let out = {}
    out["data"] = data
    out["shape"] = x["shape"]
    out["size"] = x["size"]
    out["ndim"] = x["ndim"]
    out["requires_grad"] = false
    out["grad"] = nil
    out["_grad_fn"] = nil
    return out

proc tanh_forward(x):
    import math
    let data = []
    for i in range(x["size"]):
        let ep = math.exp(x["data"][i])
        let en = math.exp(0 - x["data"][i])
        push(data, (ep - en) / (ep + en))
    let out = {}
    out["data"] = data
    out["shape"] = x["shape"]
    out["size"] = x["size"]
    out["ndim"] = x["ndim"]
    out["requires_grad"] = false
    out["grad"] = nil
    out["_grad_fn"] = nil
    return out

# ============================================================================
# Dropout
# ============================================================================

proc dropout(p):
    let layer = {}
    layer["type"] = "dropout"
    layer["p"] = p
    layer["training"] = true
    return layer

proc dropout_forward(layer, x, rng_state):
    if not layer["training"]:
        return x
    let p = layer["p"]
    let scale = 1 / (1 - p)
    let data = []
    for i in range(x["size"]):
        rng_state["v"] = (rng_state["v"] * 1664525 + 1013904223) & 4294967295
        let r = (rng_state["v"] & 65535) / 65536
        if r < p:
            push(data, 0)
        else:
            push(data, x["data"][i] * scale)
    let out = {}
    out["data"] = data
    out["shape"] = x["shape"]
    out["size"] = x["size"]
    out["ndim"] = x["ndim"]
    out["requires_grad"] = false
    out["grad"] = nil
    out["_grad_fn"] = nil
    return out

# ============================================================================
# Batch Normalization (1D)
# ============================================================================

proc batch_norm(num_features):
    let layer = {}
    layer["type"] = "batch_norm"
    layer["num_features"] = num_features
    layer["eps"] = 0.00001
    layer["momentum"] = 0.1
    layer["training"] = true
    # Learnable parameters
    let gamma = []
    let beta = []
    for i in range(num_features):
        push(gamma, 1)
        push(beta, 0)
    layer["gamma"] = gamma
    layer["beta"] = beta
    # Running statistics
    let running_mean = []
    let running_var = []
    for i in range(num_features):
        push(running_mean, 0)
        push(running_var, 1)
    layer["running_mean"] = running_mean
    layer["running_var"] = running_var
    return layer

# ============================================================================
# Sequential model
# ============================================================================

proc sequential(layers):
    let model = {}
    model["type"] = "sequential"
    model["layers"] = layers
    return model

# Forward through sequential model
proc forward(model, x):
    let out = x
    let layers = model["layers"]
    for i in range(len(layers)):
        let layer = layers[i]
        if layer["type"] == "linear":
            out = linear_forward(layer, out)
        if layer["type"] == "relu":
            out = relu_forward(out)
        if layer["type"] == "sigmoid":
            out = sigmoid_forward(out)
        if layer["type"] == "tanh":
            out = tanh_forward(out)
    return out

# ============================================================================
# Parameter collection
# ============================================================================

# Get all parameters from a model
proc parameters(model):
    let params = []
    if model["type"] == "sequential":
        let layers = model["layers"]
        for i in range(len(layers)):
            let layer = layers[i]
            if layer["type"] == "linear":
                push(params, layer["weight"])
                push(params, layer["bias"])
    if model["type"] == "linear":
        push(params, model["weight"])
        push(params, model["bias"])
    return params

# Count total parameters
proc num_parameters(model):
    let params = parameters(model)
    let total = 0
    for i in range(len(params)):
        total = total + params[i]["size"]
    return total

# Set training/eval mode
proc train(model):
    if model["type"] == "sequential":
        let layers = model["layers"]
        for i in range(len(layers)):
            if dict_has(layers[i], "training"):
                layers[i]["training"] = true

proc eval_mode(model):
    if model["type"] == "sequential":
        let layers = model["layers"]
        for i in range(len(layers)):
            if dict_has(layers[i], "training"):
                layers[i]["training"] = false
