gc_disable()
# Text generation: sampling strategies for autoregressive language models
# Supports greedy, top-k, top-p (nucleus), temperature, beam search, repetition penalty

import math

# ============================================================================
# Sampling strategies
# ============================================================================

# Greedy: pick the highest-probability token
proc greedy(logits):
    let best_idx = 0
    let best_val = logits[0]
    for i in range(len(logits)):
        if logits[i] > best_val:
            best_val = logits[i]
            best_idx = i
    return best_idx

# Apply temperature to logits (higher = more random)
proc apply_temperature(logits, temperature):
    if temperature <= 0.001:
        return logits
    let result = []
    for i in range(len(logits)):
        push(result, logits[i] / temperature)
    return result

# Softmax over logits
proc softmax(logits):
    let max_val = logits[0]
    for i in range(len(logits)):
        if logits[i] > max_val:
            max_val = logits[i]
    let exps = []
    let exp_sum = 0
    for i in range(len(logits)):
        let e = math.exp(logits[i] - max_val)
        push(exps, e)
        exp_sum = exp_sum + e
    let probs = []
    for i in range(len(exps)):
        push(probs, exps[i] / exp_sum)
    return probs

# Sample from probability distribution
proc sample_from_probs(probs, rng_seed):
    let seed = rng_seed
    seed = (seed * 1664525 + 1013904223) & 4294967295
    let r = (seed & 65535) / 65536
    let cumsum = 0
    for i in range(len(probs)):
        cumsum = cumsum + probs[i]
        if r < cumsum:
            return i
    return len(probs) - 1

# Top-K sampling: only consider the K highest-probability tokens
proc top_k_filter(logits, k):
    # Find k-th largest value
    let sorted_vals = []
    for i in range(len(logits)):
        push(sorted_vals, logits[i])
    # Partial sort: find threshold
    for i in range(k):
        let max_idx = i
        for j in range(len(sorted_vals) - i):
            if sorted_vals[i + j] > sorted_vals[max_idx]:
                max_idx = i + j
        let temp = sorted_vals[i]
        sorted_vals[i] = sorted_vals[max_idx]
        sorted_vals[max_idx] = temp
    let threshold = sorted_vals[k - 1]
    let filtered = []
    for i in range(len(logits)):
        if logits[i] >= threshold:
            push(filtered, logits[i])
        else:
            push(filtered, -10000)
    return filtered

# Top-P (nucleus) sampling: keep tokens with cumulative probability <= p
proc top_p_filter(logits, p):
    let probs = softmax(logits)
    # Sort indices by probability (descending)
    let indices = []
    for i in range(len(probs)):
        push(indices, i)
    # Selection sort by probability
    for i in range(len(indices)):
        let max_idx = i
        for j in range(len(indices) - i):
            if probs[indices[i + j]] > probs[indices[max_idx]]:
                max_idx = i + j
        let temp = indices[i]
        indices[i] = indices[max_idx]
        indices[max_idx] = temp
    # Find cutoff
    let cumsum = 0
    let cutoff_idx = len(indices)
    for i in range(len(indices)):
        cumsum = cumsum + probs[indices[i]]
        if cumsum > p:
            cutoff_idx = i + 1
            i = len(indices)
    # Zero out tokens below cutoff
    let filtered = []
    let kept = {}
    for i in range(cutoff_idx):
        if i < len(indices):
            kept[str(indices[i])] = true
    for i in range(len(logits)):
        if dict_has(kept, str(i)):
            push(filtered, logits[i])
        else:
            push(filtered, -10000)
    return filtered

# Repetition penalty: reduce logits for already-generated tokens
proc apply_repetition_penalty(logits, generated_ids, penalty):
    let result = []
    let seen = {}
    for i in range(len(generated_ids)):
        seen[str(generated_ids[i])] = true
    for i in range(len(logits)):
        if dict_has(seen, str(i)):
            if logits[i] > 0:
                push(result, logits[i] / penalty)
            else:
                push(result, logits[i] * penalty)
        else:
            push(result, logits[i])
    return result

# ============================================================================
# Generation configuration
# ============================================================================

proc create_gen_config():
    let cfg = {}
    comptime:
        cfg["max_new_tokens"] = 100
        cfg["temperature"] = 1.0
        cfg["top_k"] = 50
        cfg["top_p"] = 0.9
        cfg["repetition_penalty"] = 1.0
        cfg["do_sample"] = true
        cfg["eos_token_id"] = 2
        cfg["pad_token_id"] = 0
    return cfg

proc greedy_config():
    let cfg = create_gen_config()
    cfg["do_sample"] = false
    cfg["temperature"] = 1.0
    return cfg

proc creative_config():
    let cfg = create_gen_config()
    cfg["temperature"] = 1.2
    cfg["top_k"] = 100
    cfg["top_p"] = 0.95
    return cfg

proc precise_config():
    let cfg = create_gen_config()
    cfg["temperature"] = 0.3
    cfg["top_k"] = 10
    cfg["top_p"] = 0.5
    return cfg

# ============================================================================
# Full generation loop
# ============================================================================

# Generate token IDs given a logits function
# get_logits_fn: proc(token_ids) -> logits array
proc generate(get_logits_fn, input_ids, gen_cfg, rng_seed):
    let generated = []
    for i in range(len(input_ids)):
        push(generated, input_ids[i])
    let seed = rng_seed
    for step in range(gen_cfg["max_new_tokens"]):
        let logits = get_logits_fn(generated)
        # Apply temperature
        if gen_cfg["temperature"] != 1.0:
            logits = apply_temperature(logits, gen_cfg["temperature"])
        # Apply repetition penalty
        if gen_cfg["repetition_penalty"] > 1.0:
            logits = apply_repetition_penalty(logits, generated, gen_cfg["repetition_penalty"])
        let next_token = 0
        if gen_cfg["do_sample"]:
            # Apply top-k
            if gen_cfg["top_k"] > 0 and gen_cfg["top_k"] < len(logits):
                logits = top_k_filter(logits, gen_cfg["top_k"])
            # Apply top-p
            if gen_cfg["top_p"] < 1.0:
                logits = top_p_filter(logits, gen_cfg["top_p"])
            let probs = softmax(logits)
            seed = (seed * 1664525 + 1013904223) & 4294967295
            next_token = sample_from_probs(probs, seed)
        else:
            next_token = greedy(logits)
        push(generated, next_token)
        if next_token == gen_cfg["eos_token_id"]:
            return generated
    return generated

# ============================================================================
# Beam search
# ============================================================================

proc beam_search(get_logits_fn, input_ids, beam_width, max_len, eos_id):
    # Initialize beams
    let beams = []
    let initial = {}
    initial["ids"] = []
    for i in range(len(input_ids)):
        push(initial["ids"], input_ids[i])
    initial["score"] = 0
    push(beams, initial)
    for step in range(max_len):
        let candidates = []
        for b in range(len(beams)):
            let beam = beams[b]
            if len(beam["ids"]) > 0 and beam["ids"][len(beam["ids"]) - 1] == eos_id:
                push(candidates, beam)
                continue
            let logits = get_logits_fn(beam["ids"])
            let probs = softmax(logits)
            # Expand with top-k tokens
            for k in range(beam_width):
                let best_idx = 0
                let best_val = -10000
                for i in range(len(probs)):
                    if probs[i] > best_val:
                        let already_used = false
                        for prev in range(k):
                            if candidates[len(candidates) - 1 - prev]["ids"][len(candidates[len(candidates) - 1 - prev]["ids"]) - 1] == i:
                                already_used = true
                        if not already_used:
                            best_val = probs[i]
                            best_idx = i
                let new_beam = {}
                let new_ids = []
                for i in range(len(beam["ids"])):
                    push(new_ids, beam["ids"][i])
                push(new_ids, best_idx)
                new_beam["ids"] = new_ids
                new_beam["score"] = beam["score"] + math.log(best_val + 0.0000001)
                push(candidates, new_beam)
        # Keep top beams
        # Sort by score (simple selection sort)
        for i in range(len(candidates)):
            let max_idx = i
            for j in range(len(candidates) - i):
                if candidates[i + j]["score"] > candidates[max_idx]["score"]:
                    max_idx = i + j
            let temp = candidates[i]
            candidates[i] = candidates[max_idx]
            candidates[max_idx] = temp
        beams = []
        for i in range(beam_width):
            if i < len(candidates):
                push(beams, candidates[i])
    if len(beams) > 0:
        return beams[0]["ids"]
    return input_ids
