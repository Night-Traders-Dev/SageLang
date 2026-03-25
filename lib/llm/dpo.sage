gc_disable()
# Direct Preference Optimization (DPO)
# Alignment technique that replaces RLHF with simpler preference-based training
# Reference: Rafailov et al. 2023 - "Direct Preference Optimization"

import math

# ============================================================================
# Preference data
# ============================================================================

# Create a preference pair (chosen response > rejected response)
proc preference_pair(prompt, chosen, rejected):
    let pair = {}
    pair["prompt"] = prompt
    pair["chosen"] = chosen
    pair["rejected"] = rejected
    return pair

# Create a preference dataset
proc create_dataset():
    let ds = {}
    ds["pairs"] = []
    return ds

proc add_pair(ds, prompt, chosen, rejected):
    push(ds["pairs"], preference_pair(prompt, chosen, rejected))

# ============================================================================
# DPO Loss
# ============================================================================

# DPO loss: -log(sigmoid(beta * (log_pi_chosen - log_ref_chosen - log_pi_rejected + log_ref_rejected)))
# beta: temperature parameter (typically 0.1 - 0.5)
proc dpo_loss(log_pi_chosen, log_pi_rejected, log_ref_chosen, log_ref_rejected, beta):
    let reward_diff = beta * (log_pi_chosen - log_ref_chosen - log_pi_rejected + log_ref_rejected)
    let sigmoid_val = 1.0 / (1.0 + math.exp(0 - reward_diff))
    if sigmoid_val < 0.0000001:
        sigmoid_val = 0.0000001
    return 0 - math.log(sigmoid_val)

# Simplified DPO loss when reference model = initial policy (common case)
proc simple_dpo_loss(chosen_logprob, rejected_logprob, beta):
    let diff = beta * (chosen_logprob - rejected_logprob)
    let sigmoid_val = 1.0 / (1.0 + math.exp(0 - diff))
    if sigmoid_val < 0.0000001:
        sigmoid_val = 0.0000001
    return 0 - math.log(sigmoid_val)

# Batch DPO loss over multiple preference pairs
proc batch_dpo_loss(chosen_logprobs, rejected_logprobs, beta):
    let total = 0
    let n = len(chosen_logprobs)
    for i in range(n):
        total = total + simple_dpo_loss(chosen_logprobs[i], rejected_logprobs[i], beta)
    return total / n

# ============================================================================
# DPO Training configuration
# ============================================================================

proc create_dpo_config():
    let cfg = {}
    cfg["beta"] = 0.1
    cfg["learning_rate"] = 0.00001
    cfg["epochs"] = 1
    cfg["batch_size"] = 4
    cfg["max_length"] = 512
    cfg["warmup_ratio"] = 0.1
    cfg["gradient_clip"] = 1.0
    cfg["label_smoothing"] = 0.0
    return cfg

# ============================================================================
# ORPO (Odds Ratio Preference Optimization) - simpler alternative to DPO
# ============================================================================

proc orpo_loss(chosen_logprob, rejected_logprob, lambda_val):
    # ORPO combines SFT loss with odds ratio
    let sft_loss = 0 - chosen_logprob
    let odds_chosen = math.exp(chosen_logprob) / (1 - math.exp(chosen_logprob) + 0.0000001)
    let odds_rejected = math.exp(rejected_logprob) / (1 - math.exp(rejected_logprob) + 0.0000001)
    let odds_ratio = odds_chosen / (odds_rejected + 0.0000001)
    let or_loss = 0 - math.log(1.0 / (1.0 + math.exp(0 - math.log(odds_ratio + 0.0000001))))
    return sft_loss + lambda_val * or_loss

# ============================================================================
# Preference data generation helpers
# ============================================================================

# Generate Sage-specific preference pairs for code quality
proc sage_code_preferences():
    let ds = create_dataset()

    # Prefer idiomatic Sage over non-idiomatic
    add_pair(ds, "Write a loop that prints 1 to 10", "for i in range(10):" + chr(10) + "    print i + 1", "let i = 1" + chr(10) + "while i <= 10:" + chr(10) + "    print i" + chr(10) + "    i = i + 1")

    # Prefer gc_disable for heavy modules
    add_pair(ds, "Start a module with heavy allocation", "gc_disable()" + chr(10) + "# Heavy allocation module" + chr(10) + "let data = []", "# Heavy allocation module" + chr(10) + "let data = []")

    # Prefer dotted imports
    add_pair(ds, "Import the FAT filesystem module", "import os.fat", "import fat")

    # Prefer chr() over escape sequences
    add_pair(ds, "Print a newline in a string", "let msg = " + chr(34) + "line1" + chr(34) + " + chr(10) + " + chr(34) + "line2" + chr(34), "let msg = " + chr(34) + "line1\\nline2" + chr(34))

    # Prefer if/continue over deep elif chains
    add_pair(ds, "Handle 6 different cases", "for c in cases:" + chr(10) + "    if c == 1:" + chr(10) + "        handle1()" + chr(10) + "        continue" + chr(10) + "    if c == 2:" + chr(10) + "        handle2()" + chr(10) + "        continue", "if c == 1:" + chr(10) + "    handle1()" + chr(10) + "elif c == 2:" + chr(10) + "    handle2()" + chr(10) + "elif c == 3:" + chr(10) + "    handle3()" + chr(10) + "elif c == 4:" + chr(10) + "    handle4()" + chr(10) + "elif c == 5:" + chr(10) + "    handle5()" + chr(10) + "elif c == 6:" + chr(10) + "    handle6()")

    return ds

# ============================================================================
# Reward model (simplified)
# ============================================================================

proc create_reward_model():
    let rm = {}
    rm["preferences"] = {}
    return rm

# Record a human preference
proc record_preference(rm, prompt, chosen_response):
    rm["preferences"][prompt] = chosen_response

# Score a response based on recorded preferences
proc score_response(rm, prompt, response):
    if dict_has(rm["preferences"], prompt):
        if rm["preferences"][prompt] == response:
            return 1.0
        return 0.0
    return 0.5
