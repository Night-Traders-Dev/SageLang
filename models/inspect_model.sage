gc_disable()
# SageLLM Model Inspector - Interactive debug and visualization tool
# Usage: sage models/inspect_model.sage
#
# Trains a small model and generates visual debug output:
# - Training loss curve (SVG)
# - Weight distribution histogram (SVG)
# - Attention heatmap (SVG)
# - Architecture diagram (SVG)
# - LR schedule (SVG)
# - HTML dashboard combining all charts

import io
import ml_native
import ml.debug
import ml.viz
import ml.monitor
import llm.config
import llm.tokenizer
import llm.train
import llm.attention

print "============================================"
print "  SageLLM Model Inspector v1.0.0"
print "  Debug + Visualize + Analyze"
print "============================================"
print ""

# ============================================================================
# 1. Build a nano model for inspection
# ============================================================================

let d_model = 64
let n_layers = 2
let n_heads = 2
let d_ff = 256
let vocab = 128
let seq_len = 32
let model_name = "SageGPT-Nano"

print "[CONFIG] " + model_name
print "  d_model=" + str(d_model) + " layers=" + str(n_layers) + " heads=" + str(n_heads) + " d_ff=" + str(d_ff)
print ""

# Model summary table
let summary = debug.model_summary(model_name, n_layers, d_model, d_ff, n_heads, vocab, 256)
print summary

# ============================================================================
# 2. Initialize weights
# ============================================================================

print "[INIT] Initializing weights..."
let seed = 42
let sc = 0.02
let embed_w = []
for i in range(vocab * d_model):
    seed = (seed * 1664525 + 1013904223) & 4294967295
    push(embed_w, ((seed & 65535) / 65536 - 0.5) * 2 * sc)

let qw = []
let kw = []
let vw = []
for i in range(d_model * d_model):
    seed = (seed * 1664525 + 1013904223) & 4294967295
    push(qw, ((seed & 65535) / 65536 - 0.5) * 2 * sc)
    seed = (seed * 1664525 + 1013904223) & 4294967295
    push(kw, ((seed & 65535) / 65536 - 0.5) * 2 * sc)
    seed = (seed * 1664525 + 1013904223) & 4294967295
    push(vw, ((seed & 65535) / 65536 - 0.5) * 2 * sc)

let norm_w = []
for i in range(d_model):
    push(norm_w, 1.0)

let lm_head = []
for i in range(d_model * vocab):
    seed = (seed * 1664525 + 1013904223) & 4294967295
    push(lm_head, ((seed & 65535) / 65536 - 0.5) * 2 * sc)

# Weight analysis
print ""
print "[WEIGHTS] Initial weight statistics:"
print "  Embedding:" + debug.format_stats(debug.weight_stats(embed_w))
print "  Q proj:   " + debug.format_stats(debug.weight_stats(qw))
print "  K proj:   " + debug.format_stats(debug.weight_stats(kw))
print "  V proj:   " + debug.format_stats(debug.weight_stats(vw))
print "  LM head:  " + debug.format_stats(debug.weight_stats(lm_head))

# Weight histogram (text)
print ""
print "[WEIGHTS] Q projection weight distribution:"
let hist = debug.histogram(qw, 20)
print debug.render_histogram(hist, 40)

# ============================================================================
# 3. Train and monitor
# ============================================================================

print "[TRAIN] Loading training data..."
let corpus = io.readfile("models/data/programming_languages.txt")
if corpus == nil:
    corpus = "proc hello(): print 42"
    print "  (using fallback corpus)"
else:
    print "  Corpus: " + str(len(corpus)) + " chars"

let tok = tokenizer.char_tokenizer()
let tokens = tokenizer.encode(tok, corpus)
let examples = train.create_lm_examples(tokens, seq_len)
let num_steps = len(examples)
if num_steps > 30:
    num_steps = 30

print "  Tokens: " + str(len(tokens)) + ", Steps: " + str(num_steps)
print ""

# Create monitor
let mon = monitor.create()
let all_losses = []
let last_attn = nil

print "[TRAIN] Training with live monitoring..."
for step in range(num_steps):
    let ids = examples[step]["input_ids"]
    let tgt = examples[step]["target_ids"]
    let lr = train.cosine_schedule(step, num_steps, 5, 0.0003, 0.00001)

    # Forward pass
    let hidden = []
    for t in range(seq_len):
        let tid = ids[t]
        if tid >= vocab:
            tid = 0
        for j in range(d_model):
            push(hidden, embed_w[tid * d_model + j])

    hidden = ml_native.rms_norm(hidden, norm_w, seq_len, d_model, 0.00001)
    let q = ml_native.matmul(hidden, qw, seq_len, d_model, d_model)
    let k = ml_native.matmul(hidden, kw, seq_len, d_model, d_model)
    let v = ml_native.matmul(hidden, vw, seq_len, d_model, d_model)
    let attn_out = attention.scaled_dot_product(q, k, v, seq_len, d_model, true)
    last_attn = attn_out
    hidden = ml_native.add(hidden, attn_out)
    hidden = ml_native.rms_norm(hidden, norm_w, seq_len, d_model, 0.00001)

    let last_h = []
    for j in range(d_model):
        push(last_h, hidden[(seq_len - 1) * d_model + j])
    let logits = ml_native.matmul(last_h, lm_head, 1, d_model, vocab)

    let target = [tgt[seq_len - 1]]
    if target[0] >= vocab:
        target[0] = 0
    let loss = ml_native.cross_entropy(logits, target, 1, vocab)

    push(all_losses, loss)
    monitor.log_step(mon, loss, lr, 0, seq_len)

    if (step + 1) - (((step + 1) / 10) | 0) * 10 == 0:
        monitor.print_progress(mon, num_steps)

print ""

# ============================================================================
# 4. Training diagnostics
# ============================================================================

print "[DIAG] Training diagnostics:"
let issues = debug.diagnose_training(all_losses)
for i in range(len(issues)):
    print "  " + issues[i]
print ""

# Monitor summary
print monitor.summary(mon)

# ============================================================================
# 5. Generate visualizations
# ============================================================================

print "[VIZ] Generating SVG visualizations..."
let viz_dir = "models/viz"
io.writefile(viz_dir + "/.keep", "")

# Loss curve
viz.loss_curve(all_losses, model_name + " Training Loss", viz_dir + "/loss_curve.svg")
print "  Generated: " + viz_dir + "/loss_curve.svg"

# Weight histogram
viz.weight_histogram(qw, model_name + " Q-Projection Weights", viz_dir + "/weight_dist.svg")
print "  Generated: " + viz_dir + "/weight_dist.svg"

# Attention heatmap (use a small portion)
let attn_size = 16
let small_attn = []
for i in range(attn_size * attn_size):
    push(small_attn, 0)

if last_attn != nil:
    if attn_size > seq_len:
        attn_size = seq_len
    # Reset small_attn for actual size
    small_attn = []
    for i in range(attn_size * attn_size):
        push(small_attn, 0)
    # Build attention weights from Q*K^T
    let small_q = []
    let small_k = []
    for i in range(attn_size):
        for j in range(d_model):
            push(small_q, last_attn[i * d_model + j])
            push(small_k, last_attn[i * d_model + j])
    # Compute attention scores
    for i in range(attn_size):
        let max_val = -10000
        for j in range(attn_size):
            let dot = 0
            for d in range(d_model):
                dot = dot + small_q[i * d_model + d] * small_k[j * d_model + d]
            small_attn[i * attn_size + j] = dot
            if dot > max_val:
                max_val = dot
        # Normalize to [0,1]
        let total = 0
        for j in range(attn_size):
            import math
            let e = math.exp(small_attn[i * attn_size + j] - max_val)
            small_attn[i * attn_size + j] = e
            total = total + e
        for j in range(attn_size):
            small_attn[i * attn_size + j] = small_attn[i * attn_size + j] / total
    viz.attention_heatmap(small_attn, attn_size, model_name + " Attention", viz_dir + "/attention.svg")
    print "  Generated: " + viz_dir + "/attention.svg"
    # Attention pattern analysis
    let pattern = debug.attention_pattern(small_attn, attn_size)
    print "  Causal attention: " + str(pattern["is_causal"])

# Architecture diagram
viz.architecture_diagram(model_name, n_layers, d_model, d_ff, n_heads, viz_dir + "/architecture.svg")
print "  Generated: " + viz_dir + "/architecture.svg"

# LR schedule
viz.lr_schedule_chart(num_steps, 5, 0.0003, 0.00001, "cosine", viz_dir + "/lr_schedule.svg")
print "  Generated: " + viz_dir + "/lr_schedule.svg"

# Dashboard HTML
let dashboard_files = viz.generate_dashboard(model_name, all_losses, qw, small_attn, 16, n_layers, d_model, d_ff, n_heads, viz_dir)
print "  Generated: " + viz_dir + "/dashboard.html"

print ""
print "[BENCH] Native backend performance:"
let bench = ml_native.benchmark(d_model, 10)
print "  " + str(d_model) + "x" + str(d_model) + " matmul: " + str(bench["ms_per_matmul"]) + " ms/op, " + str(bench["gflops"]) + " GFLOPS"

print ""
print "============================================"
print "  Inspection Complete"
print "  Open " + viz_dir + "/dashboard.html in a browser"
print "  to view all charts and analysis."
print "============================================"
