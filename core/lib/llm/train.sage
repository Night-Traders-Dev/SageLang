gc_disable()
# Training loops and optimization for language models
# Supports basic training, gradient accumulation, learning rate schedules

import math

# ============================================================================
# Training configuration
# ============================================================================

proc create_train_config():
    let cfg = {}
    cfg["learning_rate"] = 0.0003
    cfg["batch_size"] = 4
    cfg["epochs"] = 1
    cfg["max_steps"] = -1
    cfg["warmup_steps"] = 100
    cfg["weight_decay"] = 0.01
    cfg["grad_clip"] = 1.0
    cfg["grad_accum_steps"] = 1
    cfg["log_interval"] = 10
    cfg["eval_interval"] = 100
    cfg["save_interval"] = 500
    cfg["lr_schedule"] = "cosine"
    cfg["min_lr"] = 0.00001
    return cfg

# ============================================================================
# Learning rate schedules
# ============================================================================

proc cosine_schedule(step, total_steps, warmup_steps, max_lr, min_lr):
    if step < warmup_steps:
        return max_lr * step / warmup_steps
    let progress = (step - warmup_steps) / (total_steps - warmup_steps)
    if progress > 1:
        progress = 1
    return min_lr + (max_lr - min_lr) * 0.5 * (1 + math.cos(math.pi * progress))

proc linear_schedule(step, total_steps, warmup_steps, max_lr, min_lr):
    if step < warmup_steps:
        return max_lr * step / warmup_steps
    let progress = (step - warmup_steps) / (total_steps - warmup_steps)
    if progress > 1:
        progress = 1
    return max_lr - (max_lr - min_lr) * progress

proc constant_schedule(step, warmup_steps, max_lr):
    if step < warmup_steps:
        return max_lr * step / warmup_steps
    return max_lr

proc get_lr(train_cfg, step, total_steps):
    let schedule = train_cfg["lr_schedule"]
    let lr = train_cfg["learning_rate"]
    let min_lr = train_cfg["min_lr"]
    let warmup = train_cfg["warmup_steps"]
    if schedule == "cosine":
        return cosine_schedule(step, total_steps, warmup, lr, min_lr)
    if schedule == "linear":
        return linear_schedule(step, total_steps, warmup, lr, min_lr)
    return constant_schedule(step, warmup, lr)

# ============================================================================
# Gradient clipping
# ============================================================================

proc clip_grad_norm(grads, max_norm):
    let total_norm = 0
    for i in range(len(grads)):
        total_norm = total_norm + grads[i] * grads[i]
    total_norm = math.sqrt(total_norm)
    if total_norm > max_norm:
        let scale = max_norm / total_norm
        for i in range(len(grads)):
            grads[i] = grads[i] * scale
    return total_norm

# ============================================================================
# Cross-entropy loss for language modeling
# ============================================================================

proc cross_entropy_loss(logits, targets, vocab_size):
    let loss = 0
    let n = len(targets)
    for i in range(n):
        # Compute log-softmax for position i
        let offset = i * vocab_size
        let max_val = logits[offset]
        for j in range(vocab_size):
            if logits[offset + j] > max_val:
                max_val = logits[offset + j]
        let log_sum = 0
        for j in range(vocab_size):
            log_sum = log_sum + math.exp(logits[offset + j] - max_val)
        log_sum = max_val + math.log(log_sum)
        let target_logit = logits[offset + targets[i]]
        loss = loss + (log_sum - target_logit)
    return loss / n

# Perplexity from loss
proc perplexity(loss):
    return math.exp(loss)

# ============================================================================
# Training state
# ============================================================================

proc create_train_state(train_cfg):
    let state = {}
    state["step"] = 0
    state["epoch"] = 0
    state["total_loss"] = 0
    state["num_tokens"] = 0
    state["best_loss"] = 999999
    state["lr"] = train_cfg["learning_rate"]
    state["grad_norm"] = 0
    state["log"] = []
    return state

proc log_step(state, loss, lr, grad_norm):
    let entry = {}
    entry["step"] = state["step"]
    entry["loss"] = loss
    entry["lr"] = lr
    entry["grad_norm"] = grad_norm
    entry["ppl"] = perplexity(loss)
    push(state["log"], entry)
    state["total_loss"] = state["total_loss"] + loss
    state["step"] = state["step"] + 1
    state["lr"] = lr
    state["grad_norm"] = grad_norm
    if loss < state["best_loss"]:
        state["best_loss"] = loss

proc avg_loss(state):
    if state["step"] == 0:
        return 0
    return state["total_loss"] / state["step"]

# ============================================================================
# Simple training loop framework
# ============================================================================

# train_step_fn: proc(batch) -> loss value
# data_loader: proc(batch_idx) -> batch dict
proc training_loop(train_cfg, train_step_fn, data_loader, num_batches, total_steps):
    let state = create_train_state(train_cfg)
    let steps_done = 0
    for epoch in range(train_cfg["epochs"]):
        state["epoch"] = epoch
        for batch_idx in range(num_batches):
            let batch = data_loader(batch_idx)
            let lr = get_lr(train_cfg, steps_done, total_steps)
            let loss = train_step_fn(batch)
            log_step(state, loss, lr, 0)
            steps_done = steps_done + 1
            if train_cfg["max_steps"] > 0 and steps_done >= train_cfg["max_steps"]:
                return state
            if steps_done > 0 and (steps_done - ((steps_done / train_cfg["log_interval"]) | 0) * train_cfg["log_interval"]) == 0:
                print "Step " + str(steps_done) + " loss=" + str(loss) + " lr=" + str(lr) + " ppl=" + str(perplexity(loss))
    return state

# ============================================================================
# Data preparation for causal LM
# ============================================================================

# Create training examples from token IDs
# Each example: input = tokens[i:i+seq_len], target = tokens[i+1:i+seq_len+1]
proc create_lm_examples(token_ids, seq_len):
    let examples = []
    let i = 0
    while i + seq_len + 1 <= len(token_ids):
        let example = {}
        let input_ids = []
        let target_ids = []
        for j in range(seq_len):
            push(input_ids, token_ids[i + j])
            push(target_ids, token_ids[i + j + 1])
        example["input_ids"] = input_ids
        example["target_ids"] = target_ids
        push(examples, example)
        i = i + seq_len
    return examples

# Create batches from examples
proc batch_examples(examples, batch_size):
    let batches = []
    let i = 0
    while i < len(examples):
        let batch = {}
        let batch_inputs = []
        let batch_targets = []
        let actual_size = 0
        for j in range(batch_size):
            if i + j < len(examples):
                push(batch_inputs, examples[i + j]["input_ids"])
                push(batch_targets, examples[i + j]["target_ids"])
                actual_size = actual_size + 1
        batch["inputs"] = batch_inputs
        batch["targets"] = batch_targets
        batch["size"] = actual_size
        push(batches, batch)
        i = i + batch_size
    return batches
