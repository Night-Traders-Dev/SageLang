gc_disable()
# Model quantization: int8 and int4 weight compression
# Reduces memory footprint for inference

import math

# ============================================================================
# Int8 quantization (per-tensor symmetric)
# ============================================================================

# Quantize float weights to int8
proc quantize_int8(weights):
    # Find max absolute value
    let max_abs = 0
    for i in range(len(weights)):
        let abs_val = weights[i]
        if abs_val < 0:
            abs_val = 0 - abs_val
        if abs_val > max_abs:
            max_abs = abs_val
    let scale = max_abs / 127
    if scale < 0.0000001:
        scale = 0.0000001
    let quantized = []
    for i in range(len(weights)):
        let q = (weights[i] / scale + 0.5) | 0
        if q > 127:
            q = 127
        if q < -127:
            q = -127
        push(quantized, q)
    let result = {}
    result["values"] = quantized
    result["scale"] = scale
    result["dtype"] = "int8"
    result["original_size"] = len(weights)
    result["compressed_size"] = len(weights)
    result["compression_ratio"] = 4.0
    return result

# Dequantize int8 back to float
proc dequantize_int8(quantized):
    let values = quantized["values"]
    let scale = quantized["scale"]
    let result = []
    for i in range(len(values)):
        push(result, values[i] * scale)
    return result

# ============================================================================
# Int4 quantization (per-group, group_size typically 32 or 128)
# ============================================================================

proc quantize_int4(weights, group_size):
    let num_groups = ((len(weights) + group_size - 1) / group_size) | 0
    let scales = []
    let quantized = []
    for g in range(num_groups):
        let start = g * group_size
        let end_idx = start + group_size
        if end_idx > len(weights):
            end_idx = len(weights)
        # Find max abs in group
        let max_abs = 0
        for i in range(end_idx - start):
            let abs_val = weights[start + i]
            if abs_val < 0:
                abs_val = 0 - abs_val
            if abs_val > max_abs:
                max_abs = abs_val
        let scale = max_abs / 7
        if scale < 0.0000001:
            scale = 0.0000001
        push(scales, scale)
        for i in range(end_idx - start):
            let q = (weights[start + i] / scale + 0.5) | 0
            if q > 7:
                q = 7
            if q < -7:
                q = -7
            push(quantized, q)
    let result = {}
    result["values"] = quantized
    result["scales"] = scales
    result["group_size"] = group_size
    result["dtype"] = "int4"
    result["original_size"] = len(weights)
    result["compressed_size"] = (len(weights) / 2) | 0
    result["compression_ratio"] = 8.0
    return result

# Dequantize int4 back to float
proc dequantize_int4(quantized):
    let values = quantized["values"]
    let scales = quantized["scales"]
    let group_size = quantized["group_size"]
    let result = []
    for i in range(len(values)):
        let group = (i / group_size) | 0
        push(result, values[i] * scales[group])
    return result

# ============================================================================
# Quantization error analysis
# ============================================================================

proc quantization_error(original, reconstructed):
    let mse = 0
    let n = len(original)
    for i in range(n):
        let diff = original[i] - reconstructed[i]
        mse = mse + diff * diff
    mse = mse / n
    let result = {}
    result["mse"] = mse
    result["rmse"] = math.sqrt(mse)
    # Signal-to-noise ratio
    let signal_power = 0
    for i in range(n):
        signal_power = signal_power + original[i] * original[i]
    signal_power = signal_power / n
    if mse > 0:
        result["snr_db"] = 10 * math.log(signal_power / mse) / math.log(10)
    else:
        result["snr_db"] = 999
    return result

# ============================================================================
# Model size estimation
# ============================================================================

proc model_size_fp32(param_count):
    return param_count * 4

proc model_size_fp16(param_count):
    return param_count * 2

proc model_size_int8(param_count):
    return param_count + (param_count / 128) * 4

proc model_size_int4(param_count):
    return (param_count / 2) | 0 + (param_count / 32) * 4

proc format_size(bytes):
    if bytes >= 1073741824:
        return str((bytes * 10 / 1073741824) | 0) + " GB"
    if bytes >= 1048576:
        return str((bytes / 1048576) | 0) + " MB"
    return str((bytes / 1024) | 0) + " KB"

proc size_comparison(param_count):
    let result = {}
    result["fp32"] = format_size(model_size_fp32(param_count))
    result["fp16"] = format_size(model_size_fp16(param_count))
    result["int8"] = format_size(model_size_int8(param_count))
    result["int4"] = format_size(model_size_int4(param_count))
    return result
