gc_disable()
# TurboQuant: Near-optimal vector quantization (ICLR 2026)
# Google Research — Zandieh & Mirrokni
#
# Two-stage compression for KV cache and weight vectors:
#   Stage 1 (PolarQuant): Random rotation + MSE-optimal scalar quantization
#   Stage 2 (QJL): 1-bit Quantized Johnson-Lindenstrauss residual correction
#
# Key properties:
#   - Data-oblivious (no training/calibration needed)
#   - Post-training quantization (no fine-tuning)
#   - Unbiased inner product estimation
#   - Near information-theoretic optimal distortion
#   - 3-bit achieves 6x memory reduction with zero accuracy loss

import math

# ============================================================================
# Random number generator (deterministic for reproducibility)
# ============================================================================

let _tq_seed = 42

proc _tq_rand():
    _tq_seed = (_tq_seed * 1664525 + 1013904223) & 4294967295
    return (_tq_seed & 16777215) / 16777216.0

proc _tq_rand_normal():
    # Box-Muller transform for Gaussian random numbers
    let u1 = _tq_rand()
    if u1 < 0.0000001:
        u1 = 0.0000001
    let u2 = _tq_rand()
    let mag = math.sqrt(-2.0 * math.log(u1))
    return mag * math.cos(2.0 * 3.14159265358979 * u2)

proc set_seed(s):
    _tq_seed = s

# ============================================================================
# Codebook construction (MSE-optimal for Beta distribution)
# Pre-computed centroids for b=1,2,3,4 bits
# These are optimal scalar quantizer centroids for the coordinate
# distribution after random rotation (approx Normal(0, 1/d))
# ============================================================================

proc _build_codebook(bits, dim):
    let scale = 1.0 / math.sqrt(dim)
    let centroids = []
    if bits == 1:
        # 2 centroids: +/- sqrt(2/(pi*d))
        let c = math.sqrt(2.0 / (3.14159265358979 * dim))
        push(centroids, 0 - c)
        push(centroids, c)
    if bits == 2:
        # 4 centroids
        push(centroids, -1.51 * scale)
        push(centroids, -0.453 * scale)
        push(centroids, 0.453 * scale)
        push(centroids, 1.51 * scale)
    if bits == 3:
        # 8 centroids (symmetric)
        push(centroids, -2.15 * scale)
        push(centroids, -1.34 * scale)
        push(centroids, -0.756 * scale)
        push(centroids, -0.245 * scale)
        push(centroids, 0.245 * scale)
        push(centroids, 0.756 * scale)
        push(centroids, 1.34 * scale)
        push(centroids, 2.15 * scale)
    if bits == 4:
        # 16 centroids (symmetric)
        let vals = [2.73, 2.07, 1.62, 1.26, 0.942, 0.677, 0.431, 0.139]
        for vi in range(len(vals)):
            push(centroids, 0 - vals[len(vals) - 1 - vi] * scale)
        for vi in range(len(vals)):
            push(centroids, vals[vi] * scale)
    let result = {}
    result["centroids"] = centroids
    result["bits"] = bits
    result["n_codes"] = len(centroids)
    return result

# ============================================================================
# Random Rotation Matrix (orthogonal via structured random signs + Hadamard-like)
# For efficiency we use a fast pseudo-random rotation: multiply by random
# signs then apply a fixed orthogonal mixing (scaled DCT-like)
# ============================================================================

proc _generate_rotation(dim):
    # Random sign flips (equivalent to diagonal of +/-1)
    let signs = []
    for i in range(dim):
        if _tq_rand() < 0.5:
            push(signs, -1.0)
        else:
            push(signs, 1.0)
    let rot = {}
    rot["signs"] = signs
    rot["dim"] = dim
    return rot

proc _apply_rotation(rot, vec):
    let d = rot["dim"]
    let signs = rot["signs"]
    # Apply sign flips
    let result = []
    for i in range(d):
        push(result, vec[i] * signs[i])
    # Apply fast Walsh-Hadamard-like mixing (pairwise butterfly)
    let stride = 1
    while stride < d:
        let i = 0
        while i < d:
            let j = i
            while j < i + stride:
                if j + stride < d:
                    let a = result[j]
                    let b = result[j + stride]
                    result[j] = a + b
                    result[j + stride] = a - b
                j = j + 1
            i = i + stride * 2
        stride = stride * 2
    # Normalize
    let norm_factor = 1.0 / math.sqrt(d)
    for i in range(d):
        result[i] = result[i] * norm_factor
    return result

proc _apply_inverse_rotation(rot, vec):
    let d = rot["dim"]
    let signs = rot["signs"]
    # Inverse of orthogonal = transpose = same operation (self-inverse for Hadamard)
    let result = []
    for i in range(d):
        push(result, vec[i])
    # Apply inverse WHT (same as forward for normalized Hadamard)
    let norm_factor = 1.0 / math.sqrt(d)
    for i in range(d):
        result[i] = result[i] * norm_factor
    let stride = 1
    while stride < d:
        let i = 0
        while i < d:
            let j = i
            while j < i + stride:
                if j + stride < d:
                    let a = result[j]
                    let b = result[j + stride]
                    result[j] = a + b
                    result[j + stride] = a - b
                j = j + 1
            i = i + stride * 2
        stride = stride * 2
    # Undo sign flips
    for i in range(d):
        result[i] = result[i] * signs[i]
    return result

# ============================================================================
# Stage 1: TurboQuant MSE (PolarQuant)
# Randomly rotates vector, then applies MSE-optimal scalar quantization
# to each coordinate independently
# ============================================================================

proc quantize_mse(vec, bits):
    let d = len(vec)
    let rot = _generate_rotation(d)
    let codebook = _build_codebook(bits, d)
    let centroids = codebook["centroids"]
    let n_codes = codebook["n_codes"]

    # Rotate
    let rotated = _apply_rotation(rot, vec)

    # Quantize each coordinate to nearest centroid
    let indices = []
    for i in range(d):
        let best_idx = 0
        let best_dist = 999999999.0
        for c in range(n_codes):
            let diff = rotated[i] - centroids[c]
            let dist = diff * diff
            if dist < best_dist:
                best_dist = dist
                best_idx = c
        push(indices, best_idx)

    let result = {}
    result["indices"] = indices
    result["rotation"] = rot
    result["codebook"] = codebook
    result["bits"] = bits
    result["dim"] = d
    return result

proc dequantize_mse(quantized):
    let indices = quantized["indices"]
    let rot = quantized["rotation"]
    let centroids = quantized["codebook"]["centroids"]
    let d = quantized["dim"]

    # Reconstruct from centroids
    let reconstructed = []
    for i in range(d):
        push(reconstructed, centroids[indices[i]])

    # Inverse rotation
    return _apply_inverse_rotation(rot, reconstructed)

# ============================================================================
# Stage 2: QJL (Quantized Johnson-Lindenstrauss)
# 1-bit sign quantization of residual vector
# Provides unbiased inner product estimation
# ============================================================================

proc _generate_jl_matrix(d):
    # Random sign matrix S (d x d) with iid +/-1 entries
    # For efficiency, store as flat array of signs
    let signs = []
    for i in range(d * d):
        if _tq_rand() < 0.5:
            push(signs, -1.0)
        else:
            push(signs, 1.0)
    let mat = {}
    mat["signs"] = signs
    mat["dim"] = d
    return mat

proc _jl_project(mat, vec):
    # Compute S * vec (matrix-vector product using sign matrix)
    let d = mat["dim"]
    let signs = mat["signs"]
    let result = []
    for i in range(d):
        let dot = 0.0
        for j in range(d):
            dot = dot + signs[i * d + j] * vec[j]
        push(result, dot)
    return result

proc quantize_qjl(vec):
    let d = len(vec)
    let mat = _generate_jl_matrix(d)

    # Compute L2 norm of residual
    let norm_sq = 0.0
    for i in range(d):
        norm_sq = norm_sq + vec[i] * vec[i]
    let norm = math.sqrt(norm_sq)

    # Project and take sign
    let projected = _jl_project(mat, vec)
    let sign_bits = []
    for i in range(d):
        if projected[i] >= 0:
            push(sign_bits, 1)
        else:
            push(sign_bits, -1)

    let result = {}
    result["sign_bits"] = sign_bits
    result["norm"] = norm
    result["jl_matrix"] = mat
    result["dim"] = d
    return result

proc dequantize_qjl(quantized):
    let sign_bits = quantized["sign_bits"]
    let norm = quantized["norm"]
    let mat = quantized["jl_matrix"]
    let d = quantized["dim"]
    let signs = mat["signs"]

    # Reconstruct: x_hat = sqrt(pi/2) / d * norm * S^T * sign_bits
    let scale = math.sqrt(3.14159265358979 / 2.0) / d * norm
    let result = []
    for j in range(d):
        let val = 0.0
        for i in range(d):
            val = val + signs[i * d + j] * sign_bits[i]
        push(result, val * scale)
    return result

# ============================================================================
# Full TurboQuant (Two-Stage: MSE + QJL)
# Achieves unbiased inner product estimation with near-optimal distortion
# ============================================================================

proc quantize(vec, bits):
    let d = len(vec)

    # Stage 1: MSE-optimal quantization at (bits-1) bits
    let mse_bits = bits - 1
    if mse_bits < 1:
        mse_bits = 1
    let mse_q = quantize_mse(vec, mse_bits)

    # Compute residual: r = x - dequant_mse(quant_mse(x))
    let reconstructed = dequantize_mse(mse_q)
    let residual = []
    for i in range(d):
        push(residual, vec[i] - reconstructed[i])

    # Stage 2: QJL on residual (1 bit)
    let qjl_q = quantize_qjl(residual)

    let result = {}
    result["mse"] = mse_q
    result["qjl"] = qjl_q
    result["bits"] = bits
    result["dim"] = d
    return result

proc dequantize(quantized):
    # Reconstruct from both stages
    let mse_recon = dequantize_mse(quantized["mse"])
    let qjl_recon = dequantize_qjl(quantized["qjl"])
    let d = quantized["dim"]

    let result = []
    for i in range(d):
        push(result, mse_recon[i] + qjl_recon[i])
    return result

# ============================================================================
# KV Cache Compression
# Quantize key and value vectors for memory-efficient attention
# ============================================================================

proc create_kv_cache(max_seq_len, d_model, bits):
    let cache = {}
    cache["max_seq_len"] = max_seq_len
    cache["d_model"] = d_model
    cache["bits"] = bits
    cache["keys"] = []
    cache["values"] = []
    cache["length"] = 0
    # Compression stats
    cache["original_bytes"] = 0
    cache["compressed_bytes"] = 0
    return cache

proc cache_push(cache, key_vec, value_vec):
    let bits = cache["bits"]
    # Quantize key (for attention score computation — use full TurboQuant for unbiased inner products)
    let q_key = quantize(key_vec, bits)
    push(cache["keys"], q_key)
    # Quantize value (for weighted sum — MSE-only is sufficient)
    let q_val = quantize_mse(value_vec, bits)
    push(cache["values"], q_val)
    cache["length"] = cache["length"] + 1
    # Track compression ratio
    let d = cache["d_model"]
    cache["original_bytes"] = cache["original_bytes"] + d * 4 * 2
    let key_bits = d * bits + d + 32
    let val_bits = d * bits
    cache["compressed_bytes"] = cache["compressed_bytes"] + ((key_bits + val_bits + 7) / 8) | 0

proc cache_get_key(cache, idx):
    return dequantize(cache["keys"][idx])

proc cache_get_value(cache, idx):
    return dequantize_mse(cache["values"][idx])

proc cache_stats(cache):
    let stats = {}
    stats["length"] = cache["length"]
    stats["bits"] = cache["bits"]
    stats["d_model"] = cache["d_model"]
    if cache["original_bytes"] > 0:
        stats["compression_ratio"] = cache["original_bytes"] / cache["compressed_bytes"]
    else:
        stats["compression_ratio"] = 0
    stats["original_bytes"] = cache["original_bytes"]
    stats["compressed_bytes"] = cache["compressed_bytes"]
    return stats

# ============================================================================
# Distortion Analysis
# ============================================================================

proc mse_distortion(original, reconstructed):
    let d = len(original)
    let mse = 0.0
    for i in range(d):
        let diff = original[i] - reconstructed[i]
        mse = mse + diff * diff
    return mse / d

proc inner_product_error(x, y, x_hat):
    # Measure error in inner product estimation
    let true_ip = 0.0
    let est_ip = 0.0
    for i in range(len(x)):
        true_ip = true_ip + x[i] * y[i]
        est_ip = est_ip + x_hat[i] * y[i]
    let result = {}
    result["true_ip"] = true_ip
    result["estimated_ip"] = est_ip
    result["absolute_error"] = est_ip - true_ip
    if true_ip > 0.0001 or true_ip < -0.0001:
        result["relative_error"] = (est_ip - true_ip) / true_ip
    else:
        result["relative_error"] = 0
    return result

proc theoretical_mse_bound(bits):
    # D_mse <= (sqrt(3) * pi / 2) * (1/4^b)
    return (math.sqrt(3.0) * 3.14159265358979 / 2.0) * (1.0 / math.pow(4, bits))

proc theoretical_ip_bound(bits, d, y_norm_sq):
    # D_prod <= (sqrt(3) * pi^2 * ||y||^2 / d) * (1/4^b)
    return (math.sqrt(3.0) * 3.14159265358979 * 3.14159265358979 * y_norm_sq / d) * (1.0 / math.pow(4, bits))

# ============================================================================
# Utility: vector operations
# ============================================================================

proc vec_norm(v):
    let s = 0.0
    for i in range(len(v)):
        s = s + v[i] * v[i]
    return math.sqrt(s)

proc vec_normalize(v):
    let n = vec_norm(v)
    if n < 0.0000001:
        return v
    let result = []
    for i in range(len(v)):
        push(result, v[i] / n)
    return result

proc vec_dot(a, b):
    let s = 0.0
    for i in range(len(a)):
        s = s + a[i] * b[i]
    return s

proc vec_random(d):
    let v = []
    for i in range(d):
        push(v, _tq_rand_normal())
    return vec_normalize(v)

# ============================================================================
# Summary and benchmarking
# ============================================================================

proc benchmark(dim, bits, num_vectors):
    set_seed(42)
    let total_mse = 0.0
    let total_ip_err = 0.0
    let pairs = 0

    let vectors = []
    let quantized = []
    for i in range(num_vectors):
        let v = vec_random(dim)
        push(vectors, v)
        push(quantized, quantize(v, bits))

    # MSE distortion
    for i in range(num_vectors):
        let recon = dequantize(quantized[i])
        total_mse = total_mse + mse_distortion(vectors[i], recon)

    # Inner product error (pairwise sample)
    let ip_tests = num_vectors
    if ip_tests > 10:
        ip_tests = 10
    for i in range(ip_tests):
        let j = (i + 1) - (((i + 1) / num_vectors) | 0) * num_vectors
        let recon_i = dequantize(quantized[i])
        let err = inner_product_error(vectors[i], vectors[j], recon_i)
        let ae = err["absolute_error"]
        if ae < 0:
            ae = 0 - ae
        total_ip_err = total_ip_err + ae
        pairs = pairs + 1

    let result = {}
    result["dim"] = dim
    result["bits"] = bits
    result["num_vectors"] = num_vectors
    result["avg_mse"] = total_mse / num_vectors
    result["avg_ip_error"] = total_ip_err / pairs
    result["theoretical_mse_bound"] = theoretical_mse_bound(bits)
    result["compression_ratio"] = 32.0 / bits
    return result

proc summary(bench_result):
    let s = "TurboQuant Benchmark:" + chr(10)
    s = s + "  dim=" + str(bench_result["dim"]) + " bits=" + str(bench_result["bits"]) + " vectors=" + str(bench_result["num_vectors"]) + chr(10)
    s = s + "  Avg MSE: " + str(bench_result["avg_mse"]) + chr(10)
    s = s + "  Theoretical MSE bound: " + str(bench_result["theoretical_mse_bound"]) + chr(10)
    s = s + "  Avg IP error: " + str(bench_result["avg_ip_error"]) + chr(10)
    s = s + "  Compression ratio: " + str(bench_result["compression_ratio"]) + "x" + chr(10)
    return s
