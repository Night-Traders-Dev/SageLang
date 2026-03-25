gc_disable()
# SL-TQ-LLM Generative Chatbot
# Loads trained weights, runs real transformer forward pass
# Compile: sage --compile-llvm models/sl_tq_llm_chat.sage -o sl_tq_chat

import ml_native

# === Load weights via C parser (avoids OOM) ===
print "Loading SL-TQ-LLM weights..."
let W = ml_native.load_weights("models/sl_tq_llm.weights")
if W == nil:
    print "ERROR: models/sl_tq_llm.weights not found."

let cfg_parts = W[0]
let d_model = cfg_parts[0] | 0
let n_heads = cfg_parts[1] | 0
let n_layers = cfg_parts[2] | 0
let d_ff = cfg_parts[3] | 0
let vocab = cfg_parts[4] | 0
let max_seq = cfg_parts[5] | 0

let embed_w = W[1]
let qw = W[2]
let kw = W[3]
let vw = W[4]
let ow = W[5]
let gate_w = W[6]
let up_w = W[7]
let down_w = W[8]
let norm1_w = W[9]
let norm2_w = W[10]
let final_norm_w = W[11]
let lm_head_w = W[12]

let total_p = len(embed_w) + len(qw) + len(kw) + len(vw) + len(ow) + len(gate_w) + len(up_w) + len(down_w) + len(lm_head_w)
print "Loaded: d=" + str(d_model) + " ff=" + str(d_ff) + " vocab=" + str(vocab) + " params=" + str(total_p)

# === Transformer forward pass ===
proc forward(token_ids):
    # Use native C forward pass (matches train_step exactly: causal mask + softmax)
    return ml_native.forward_pass(embed_w, qw, kw, vw, ow, gate_w, up_w, down_w, norm1_w, norm2_w, final_norm_w, lm_head_w, token_ids, d_model, d_ff, vocab, len(token_ids))

# === Token sampling with temperature ===
let rng = 12345
proc sample_token(logits, temperature):
    # Apply temperature
    let scaled = []
    for i in range(len(logits)):
        push(scaled, logits[i] / temperature)
    # Softmax
    let max_val = scaled[0]
    for i in range(len(scaled)):
        if scaled[i] > max_val:
            max_val = scaled[i]
    let sum_exp = 0.0
    let probs = []
    for i in range(len(scaled)):
        let e = 1.0
        let x = scaled[i] - max_val
        # Approximate exp(x) using Taylor series
        if x > -10:
            e = 1.0 + x + x*x/2.0 + x*x*x/6.0 + x*x*x*x/24.0
            if e < 0:
                e = 0.0001
        else:
            e = 0.0001
        push(probs, e)
        sum_exp = sum_exp + e
    # Normalize
    for i in range(len(probs)):
        probs[i] = probs[i] / sum_exp
    # Sample from distribution
    rng = (rng * 1664525 + 1013904223) & 4294967295
    let r = (rng & 65535) / 65536.0
    let cumul = 0.0
    for i in range(len(probs)):
        cumul = cumul + probs[i]
        if cumul >= r:
            return i
    return len(probs) - 1

# === Generate text from prompt ===
proc generate(prompt_text, max_tokens, temperature):
    # Tokenize: character-level (ASCII)
    let ids = []
    for i in range(len(prompt_text)):
        push(ids, ord(prompt_text[i]))
    # Truncate to max_seq
    if len(ids) > max_seq:
        let trimmed = []
        for i in range(max_seq):
            push(trimmed, ids[len(ids) - max_seq + i])
        ids = trimmed
    # Generate tokens
    let output = ""
    for step in range(max_tokens):
        let logits = forward(ids)
        let next_id = sample_token(logits, temperature)
        if next_id < 32 or next_id > 126:
            next_id = 32
        output = output + chr(next_id)
        push(ids, next_id)
        # Slide window
        if len(ids) > max_seq:
            let new_ids = []
            for ni in range(max_seq):
                push(new_ids, ids[len(ids) - max_seq + ni])
            ids = new_ids
    return output

# === Main loop ===
print "============================================"
print "  SL-TQ-LLM Generative Chat v1.0"
print "  Real transformer inference from weights"
print "============================================"
print "Type a prompt and I will generate a continuation."
print "Commands: quit, temp <0.1-2.0>, len <1-200>"
print ""

let gen_temp = 0.8
let gen_len = 50
let running = true
while running:
    let msg = input("Prompt> ")
    if msg == "quit" or msg == "exit":
        running = false
        print "Goodbye!"
    if running and len(msg) > 5 and msg[0] == "t" and msg[1] == "e" and msg[2] == "m" and msg[3] == "p" and msg[4] == " ":
        let tv = ""
        for i in range(len(msg) - 5):
            tv = tv + msg[5 + i]
        gen_temp = tonumber(tv)
        if gen_temp < 0.1:
            gen_temp = 0.1
        if gen_temp > 2.0:
            gen_temp = 2.0
        print "  Temperature set to " + str(gen_temp)
    if running and len(msg) > 4 and msg[0] == "l" and msg[1] == "e" and msg[2] == "n" and msg[3] == " ":
        let lv = ""
        for i in range(len(msg) - 4):
            lv = lv + msg[4 + i]
        gen_len = tonumber(lv) | 0
        if gen_len < 1:
            gen_len = 1
        if gen_len > 200:
            gen_len = 200
        print "  Max length set to " + str(gen_len)
    if running and msg != "quit" and msg != "exit":
        let is_cmd = false
        if len(msg) > 4 and msg[0] == "t" and msg[1] == "e" and msg[2] == "m":
            is_cmd = true
        if len(msg) > 3 and msg[0] == "l" and msg[1] == "e" and msg[2] == "n":
            is_cmd = true
        if not is_cmd:
            print ""
            print "  [Generating " + str(gen_len) + " tokens at temp=" + str(gen_temp) + "...]"
            let result = generate(msg, gen_len, gen_temp)
            print ""
            print "SL-TQ-LLM> " + msg + result
            print ""
