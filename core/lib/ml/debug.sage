gc_disable()
# Neural network debug and inspection tools
# Weight statistics, activation analysis, gradient checking, model summaries

import math

# ============================================================================
# Weight statistics
# ============================================================================

# Compute stats for a flat weight array
proc weight_stats(weights):
    let n = len(weights)
    if n == 0:
        return {"count": 0, "mean": 0, "std": 0, "min": 0, "max": 0, "norm": 0, "zeros": 0, "sparsity": 0}
    let s = {}
    s["count"] = n
    # Mean
    let total = 0
    for i in range(n):
        total = total + weights[i]
    s["mean"] = total / n
    # Variance / std
    let var_sum = 0
    for i in range(n):
        let d = weights[i] - s["mean"]
        var_sum = var_sum + d * d
    s["std"] = math.sqrt(var_sum / n)
    # Min / Max
    let mn = weights[0]
    let mx = weights[0]
    for i in range(n):
        if weights[i] < mn:
            mn = weights[i]
        if weights[i] > mx:
            mx = weights[i]
    s["min"] = mn
    s["max"] = mx
    # L2 norm
    let norm = 0
    for i in range(n):
        norm = norm + weights[i] * weights[i]
    s["norm"] = math.sqrt(norm)
    # Sparsity (count near-zero weights)
    let zeros = 0
    for i in range(n):
        let abs_val = weights[i]
        if abs_val < 0:
            abs_val = 0 - abs_val
        if abs_val < 0.0001:
            zeros = zeros + 1
    s["zeros"] = zeros
    s["sparsity"] = zeros / n
    return s

# Format weight stats as readable string
proc format_stats(stats):
    let nl = chr(10)
    let out = "  count=" + str(stats["count"])
    out = out + " mean=" + str(stats["mean"])
    out = out + " std=" + str(stats["std"])
    out = out + " min=" + str(stats["min"])
    out = out + " max=" + str(stats["max"])
    out = out + " norm=" + str(stats["norm"])
    out = out + " sparsity=" + str((stats["sparsity"] * 100) | 0) + "%"
    return out

# ============================================================================
# Histogram (text-based)
# ============================================================================

# Build a histogram of values into bins
proc histogram(values, num_bins):
    if len(values) == 0:
        return {"bins": [], "counts": [], "min": 0, "max": 0}
    let mn = values[0]
    let mx = values[0]
    for i in range(len(values)):
        if values[i] < mn:
            mn = values[i]
        if values[i] > mx:
            mx = values[i]
    let bin_width = (mx - mn) / num_bins
    if bin_width < 0.0000001:
        bin_width = 1
    let counts = []
    let bins = []
    for i in range(num_bins):
        push(counts, 0)
        push(bins, mn + i * bin_width)
    for i in range(len(values)):
        let idx = ((values[i] - mn) / bin_width) | 0
        if idx >= num_bins:
            idx = num_bins - 1
        if idx < 0:
            idx = 0
        counts[idx] = counts[idx] + 1
    let h = {}
    h["bins"] = bins
    h["counts"] = counts
    h["min"] = mn
    h["max"] = mx
    h["bin_width"] = bin_width
    return h

# Render histogram as text art
proc render_histogram(hist, width):
    let nl = chr(10)
    let counts = hist["counts"]
    let bins = hist["bins"]
    let max_count = 1
    for i in range(len(counts)):
        if counts[i] > max_count:
            max_count = counts[i]
    let out = ""
    for i in range(len(counts)):
        let label = str((bins[i] * 100) | 0)
        while len(label) < 6:
            label = " " + label
        let bar_len = ((counts[i] * width) / max_count) | 0
        let bar = ""
        for j in range(bar_len):
            bar = bar + "#"
        out = out + label + " |" + bar + " " + str(counts[i]) + nl
    return out

# ============================================================================
# Activation analysis
# ============================================================================

# Check for dead neurons (always zero output)
proc find_dead_neurons(activations, threshold):
    let n = len(activations)
    let dead = []
    for i in range(n):
        let abs_val = activations[i]
        if abs_val < 0:
            abs_val = 0 - abs_val
        if abs_val < threshold:
            push(dead, i)
    return dead

# Check for saturated neurons (always at max/min)
proc find_saturated(activations, low_thresh, high_thresh):
    let saturated = []
    for i in range(len(activations)):
        if activations[i] <= low_thresh or activations[i] >= high_thresh:
            push(saturated, i)
    return saturated

# Activation distribution summary
proc activation_summary(activations):
    let stats = weight_stats(activations)
    let dead = find_dead_neurons(activations, 0.0001)
    let sat = find_saturated(activations, -0.99, 0.99)
    stats["dead_count"] = len(dead)
    stats["saturated_count"] = len(sat)
    stats["dead_pct"] = len(dead) / len(activations) * 100
    stats["saturated_pct"] = len(sat) / len(activations) * 100
    return stats

# ============================================================================
# Gradient checking (numerical)
# ============================================================================

# Numerical gradient check: compare analytic gradient with finite differences
proc gradient_check(fn, params, analytic_grad, epsilon):
    let max_diff = 0
    let diffs = []
    let check_count = len(params)
    if check_count > 100:
        check_count = 100
    for i in range(check_count):
        let orig = params[i]
        # f(x + eps)
        params[i] = orig + epsilon
        let f_plus = fn(params)
        # f(x - eps)
        params[i] = orig - epsilon
        let f_minus = fn(params)
        # Restore
        params[i] = orig
        let numerical = (f_plus - f_minus) / (2 * epsilon)
        let diff = numerical - analytic_grad[i]
        if diff < 0:
            diff = 0 - diff
        let denom = numerical + analytic_grad[i]
        if denom < 0:
            denom = 0 - denom
        if denom < 0.0000001:
            denom = 0.0000001
        let relative = diff / denom
        push(diffs, relative)
        if relative > max_diff:
            max_diff = relative
    let result = {}
    result["max_relative_diff"] = max_diff
    result["passed"] = max_diff < 0.001
    result["diffs"] = diffs
    result["checked"] = check_count
    return result

# ============================================================================
# Model summary
# ============================================================================

proc model_summary(name, layers, d_model, d_ff, n_heads, vocab_size, context_len):
    let nl = chr(10)
    let d_head = (d_model / n_heads) | 0
    # Parameter counts
    let embed_params = vocab_size * d_model
    let attn_params = 4 * d_model * d_model
    let ffn_params = 2 * d_model * d_ff
    let norm_params = 2 * d_model
    let per_layer = attn_params + ffn_params + norm_params
    let total = embed_params + layers * per_layer + d_model + d_model * vocab_size
    let out = "Model: " + name + nl
    out = out + "================================================" + nl
    out = out + "Layer            | Shape              | Params" + nl
    out = out + "------------------------------------------------" + nl
    out = out + "Embedding        | " + str(vocab_size) + " x " + str(d_model) + "          | " + str(embed_params) + nl
    out = out + "------------------------------------------------" + nl
    for i in range(layers):
        out = out + "Layer " + str(i) + nl
        out = out + "  RMSNorm        | " + str(d_model) + "                | " + str(d_model) + nl
        out = out + "  Q projection   | " + str(d_model) + " x " + str(d_model) + "        | " + str(d_model * d_model) + nl
        out = out + "  K projection   | " + str(d_model) + " x " + str(d_model) + "        | " + str(d_model * d_model) + nl
        out = out + "  V projection   | " + str(d_model) + " x " + str(d_model) + "        | " + str(d_model * d_model) + nl
        out = out + "  O projection   | " + str(d_model) + " x " + str(d_model) + "        | " + str(d_model * d_model) + nl
        out = out + "  RMSNorm        | " + str(d_model) + "                | " + str(d_model) + nl
        out = out + "  FFN up         | " + str(d_model) + " x " + str(d_ff) + "        | " + str(d_model * d_ff) + nl
        out = out + "  FFN down       | " + str(d_ff) + " x " + str(d_model) + "        | " + str(d_ff * d_model) + nl
    out = out + "------------------------------------------------" + nl
    out = out + "Final norm       | " + str(d_model) + "                | " + str(d_model) + nl
    out = out + "LM Head          | " + str(d_model) + " x " + str(vocab_size) + "          | " + str(d_model * vocab_size) + nl
    out = out + "================================================" + nl
    out = out + "Total parameters:  " + str(total) + nl
    out = out + "Memory (fp32):     " + str((total * 4 / 1048576) | 0) + " MB" + nl
    out = out + "Memory (fp16):     " + str((total * 2 / 1048576) | 0) + " MB" + nl
    out = out + "Memory (int8):     " + str((total / 1048576) | 0) + " MB" + nl
    out = out + "Context window:    " + str(context_len) + " tokens" + nl
    out = out + "Attention heads:   " + str(n_heads) + " (d_head=" + str(d_head) + ")" + nl
    return out

# ============================================================================
# Training diagnostics
# ============================================================================

# Detect training issues from loss history
proc diagnose_training(loss_history):
    let issues = []
    let n = len(loss_history)
    if n < 5:
        push(issues, "Too few data points for diagnosis (need 5+)")
        return issues
    # Check for NaN/Inf
    for i in range(n):
        if loss_history[i] != loss_history[i]:
            push(issues, "NaN loss detected at step " + str(i))
    # Check for divergence (loss increasing)
    let increasing = 0
    for i in range(n - 1):
        if loss_history[i + 1] > loss_history[i] * 1.1:
            increasing = increasing + 1
    if increasing > n / 2:
        push(issues, "Loss diverging - learning rate may be too high")
    # Check for plateau (loss not decreasing)
    let first_half = 0
    let second_half = 0
    let mid = (n / 2) | 0
    for i in range(mid):
        first_half = first_half + loss_history[i]
    for i in range(n - mid):
        second_half = second_half + loss_history[mid + i]
    first_half = first_half / mid
    second_half = second_half / (n - mid)
    let improvement = (first_half - second_half) / first_half
    if improvement < 0.01:
        push(issues, "Loss plateaued - try lower learning rate or more data")
    if improvement < 0:
        push(issues, "Loss increased overall - training is diverging")
    # Check final loss magnitude
    let final = loss_history[n - 1]
    if final > 10:
        push(issues, "Final loss very high (" + str(final) + ") - model may not be learning")
    if len(issues) == 0:
        push(issues, "Training looks healthy")
    return issues

# ============================================================================
# Attention pattern analysis
# ============================================================================

# Extract attention pattern (which positions attend to which)
proc attention_pattern(attn_weights, seq_len):
    let pattern = {}
    pattern["seq_len"] = seq_len
    # Find strongest attention per position
    let dominant = []
    for i in range(seq_len):
        let max_j = 0
        let max_w = attn_weights[i * seq_len]
        for j in range(seq_len):
            if attn_weights[i * seq_len + j] > max_w:
                max_w = attn_weights[i * seq_len + j]
                max_j = j
        let entry = {}
        entry["from"] = i
        entry["to"] = max_j
        entry["weight"] = max_w
        push(dominant, entry)
    pattern["dominant"] = dominant
    # Check if attention is causal (lower-triangular)
    let causal = true
    for i in range(seq_len):
        for j in range(seq_len):
            if j > i and attn_weights[i * seq_len + j] > 0.01:
                causal = false
    pattern["is_causal"] = causal
    return pattern

# Render attention heatmap as text
proc render_attention(attn_weights, seq_len, width):
    let nl = chr(10)
    let out = "Attention heatmap (" + str(seq_len) + "x" + str(seq_len) + "):" + nl
    let chars = " .:-=+*#@"
    for i in range(seq_len):
        let row = ""
        for j in range(seq_len):
            let w = attn_weights[i * seq_len + j]
            let idx = (w * 8) | 0
            if idx > 8:
                idx = 8
            if idx < 0:
                idx = 0
            row = row + chars[idx]
        out = out + row + nl
    return out
