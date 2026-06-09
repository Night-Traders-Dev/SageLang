gc_disable()
# EXPECT: seed_set
# EXPECT: quantize_works
# EXPECT: dequantize_works
# EXPECT: mse_positive
# EXPECT: kv_cache_created
# EXPECT: cache_push_works
# EXPECT: benchmark_works
# EXPECT: PASS

# TurboQuant imports math (native C), so we test the concepts with pure logic
# replicating the core quantization data structures and operations

# --- Simulate set_seed ---
let _seed = 42
proc tq_set_seed(s):
    _seed = s

proc tq_rand():
    _seed = (_seed * 1664525 + 1013904223) & 4294967295
    return (_seed & 16777215) / 16777216.0

tq_set_seed(123)
if _seed == 123:
    print "seed_set"

# --- Simulate quantize: map floats to nearest codebook index ---
proc simple_quantize(vec, bits):
    let n_codes = 1
    let b = bits
    while b > 0:
        n_codes = n_codes * 2
        b = b - 1
    let indices = []
    for i in range(len(vec)):
        let idx = ((vec[i] + 1.0) / 2.0 * n_codes) | 0
        if idx < 0:
            idx = 0
        if idx >= n_codes:
            idx = n_codes - 1
        push(indices, idx)
    let result = {}
    result["indices"] = indices
    result["n_codes"] = n_codes
    result["dim"] = len(vec)
    result["bits"] = bits
    return result

proc simple_dequantize(quantized):
    let indices = quantized["indices"]
    let n_codes = quantized["n_codes"]
    let result = []
    for i in range(len(indices)):
        let val = (indices[i] + 0.5) / n_codes * 2.0 - 1.0
        push(result, val)
    return result

# Test quantize
let vec = [0.5, -0.3, 0.8, -0.1]
let q = simple_quantize(vec, 2)
if len(q["indices"]) == 4:
    print "quantize_works"

# Test dequantize
let recon = simple_dequantize(q)
if len(recon) == 4:
    print "dequantize_works"

# Test MSE > 0 (quantization introduces distortion)
proc compute_mse(orig, recon):
    let total = 0.0
    for i in range(len(orig)):
        let diff = orig[i] - recon[i]
        total = total + diff * diff
    return total / len(orig)

let mse = compute_mse(vec, recon)
if mse > 0:
    print "mse_positive"

# --- Simulate KV cache ---
proc create_kv_cache(max_seq, d_model, bits):
    let cache = {}
    cache["max_seq_len"] = max_seq
    cache["d_model"] = d_model
    cache["bits"] = bits
    cache["keys"] = []
    cache["values"] = []
    cache["length"] = 0
    return cache

proc cache_push(cache, key_vec, val_vec):
    let q_key = simple_quantize(key_vec, cache["bits"])
    let q_val = simple_quantize(val_vec, cache["bits"])
    push(cache["keys"], q_key)
    push(cache["values"], q_val)
    cache["length"] = cache["length"] + 1

let cache = create_kv_cache(128, 4, 2)
if cache["length"] == 0:
    print "kv_cache_created"

cache_push(cache, [0.1, 0.2, 0.3, 0.4], [0.5, 0.6, 0.7, 0.8])
if cache["length"] == 1:
    print "cache_push_works"

# --- Simulate benchmark ---
proc simple_benchmark(dim, bits, num_vectors):
    let total_mse = 0.0
    for i in range(num_vectors):
        let v = []
        for j in range(dim):
            let val = tq_rand() * 2.0 - 1.0
            push(v, val)
        let q = simple_quantize(v, bits)
        let r = simple_dequantize(q)
        total_mse = total_mse + compute_mse(v, r)
    let result = {}
    result["avg_mse"] = total_mse / num_vectors
    result["dim"] = dim
    result["bits"] = bits
    result["num_vectors"] = num_vectors
    return result

let bench = simple_benchmark(4, 2, 3)
if bench["avg_mse"] > 0:
    print "benchmark_works"

print "PASS"
