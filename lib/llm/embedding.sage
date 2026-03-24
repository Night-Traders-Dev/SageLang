gc_disable()
# Token and positional embeddings for transformer models

import math

# ============================================================================
# Token Embedding Layer
# ============================================================================

# Create a token embedding table
# vocab_size: number of tokens
# d_model: embedding dimension
proc create_embedding(vocab_size, d_model):
    let emb = {}
    emb["vocab_size"] = vocab_size
    emb["d_model"] = d_model
    # Initialize with small random values (Xavier-like)
    let scale = 1.0 / math.sqrt(d_model)
    let weight = []
    let seed = vocab_size * 7 + d_model * 13
    for i in range(vocab_size * d_model):
        seed = (seed * 1664525 + 1013904223) & 4294967295
        let val = ((seed & 65535) / 65536 - 0.5) * 2 * scale
        push(weight, val)
    emb["weight"] = weight
    return emb

# Look up embeddings for a sequence of token IDs
# Returns flat array of shape [seq_len * d_model]
proc lookup(emb, token_ids):
    let d = emb["d_model"]
    let result = []
    for i in range(len(token_ids)):
        let token_id = token_ids[i]
        let offset = token_id * d
        for j in range(d):
            push(result, emb["weight"][offset + j])
    return result

# ============================================================================
# Positional Encoding
# ============================================================================

# Sinusoidal positional encoding (fixed, not learned)
proc sinusoidal_encoding(max_len, d_model):
    let pe = []
    for pos in range(max_len):
        for i in range(d_model):
            let dim = (i / 2) | 0
            let angle = pos / math.pow(10000, 2 * dim / d_model)
            if (i & 1) == 0:
                push(pe, math.sin(angle))
            else:
                push(pe, math.cos(angle))
    let result = {}
    result["data"] = pe
    result["max_len"] = max_len
    result["d_model"] = d_model
    result["type"] = "sinusoidal"
    return result

# Learned positional embedding
proc learned_position_embedding(max_len, d_model):
    let emb = create_embedding(max_len, d_model)
    emb["type"] = "learned_position"
    emb["max_len"] = max_len
    return emb

# RoPE (Rotary Position Embedding) - precompute frequencies
proc rope_frequencies(d_head, max_len, theta):
    let freqs = []
    for pos in range(max_len):
        let pos_freqs = []
        let half_d = (d_head / 2) | 0
        for i in range(half_d):
            let freq = 1.0 / math.pow(theta, 2 * i / d_head)
            let angle = pos * freq
            push(pos_freqs, math.cos(angle))
            push(pos_freqs, math.sin(angle))
        push(freqs, pos_freqs)
    let result = {}
    result["data"] = freqs
    result["d_head"] = d_head
    result["max_len"] = max_len
    result["type"] = "rope"
    return result

# Apply RoPE to a vector at a given position
proc apply_rope(vec, freqs, pos):
    let pos_freqs = freqs["data"][pos]
    let half_d = (len(vec) / 2) | 0
    let result = []
    for i in range(half_d):
        let cos_val = pos_freqs[i * 2]
        let sin_val = pos_freqs[i * 2 + 1]
        let x0 = vec[i * 2]
        let x1 = vec[i * 2 + 1]
        push(result, x0 * cos_val - x1 * sin_val)
        push(result, x0 * sin_val + x1 * cos_val)
    return result

# ============================================================================
# Add embeddings (token + position)
# ============================================================================

# Add positional encoding to token embeddings
# token_embs: flat array [seq_len * d_model]
# pos_enc: positional encoding data
# seq_len: number of tokens
proc add_position(token_embs, pos_enc, seq_len):
    let d = pos_enc["d_model"]
    let result = []
    for i in range(seq_len):
        for j in range(d):
            let tok_val = token_embs[i * d + j]
            let pos_val = pos_enc["data"][i * d + j]
            push(result, tok_val + pos_val)
    return result

# Get position IDs for a sequence
proc position_ids(seq_len, offset):
    let ids = []
    for i in range(seq_len):
        push(ids, offset + i)
    return ids

# ============================================================================
# Embedding utilities
# ============================================================================

# Scale embeddings by sqrt(d_model) (common in transformer architectures)
proc scale_embeddings(embs, d_model):
    let factor = math.sqrt(d_model)
    let result = []
    for i in range(len(embs)):
        push(result, embs[i] * factor)
    return result

# Dropout on embeddings (zeroes random elements)
proc embedding_dropout(embs, drop_rate, seed):
    let result = []
    let s = seed
    for i in range(len(embs)):
        s = (s * 1664525 + 1013904223) & 4294967295
        let r = (s & 65535) / 65536
        if r < drop_rate:
            push(result, 0)
        else:
            push(result, embs[i] / (1 - drop_rate))
    return result
