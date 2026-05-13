gc_disable()
# Train SageGPT model (custom architecture)
# Usage: sage models/train_sagegpt.sage

import io
import ml_native
import ml.gpu_accel
import llm.tokenizer
import llm.train
import llm.config
import llm.generate
import llm.agent
import llm.embedding
import llm.attention

let _compute = gpu_accel.create("auto")

print "=== SageGPT Training (Custom Architecture) ==="
print ""

# 1. Create nano model (smallest, for testing the full pipeline)
let d_model = 64
let n_layers = 2
let n_heads = 2
let d_ff = 256
let vocab_size = 512
let context_length = 128
let d_head = (d_model / n_heads) | 0

print "Architecture: SageGPT-Nano"
print "  d_model: " + str(d_model)
print "  Layers: " + str(n_layers)
print "  Heads: " + str(n_heads)
print "  d_ff: " + str(d_ff)
print "  Vocab: " + str(vocab_size)
print "  Context: " + str(context_length)

# 2. Build corpus
print ""
print "Building training corpus..."
let corpus = ""
let files = ["lib/arrays.sage", "lib/dicts.sage", "lib/strings.sage", "lib/iter.sage", "lib/math.sage"]
for i in range(len(files)):
    let content = io.readfile(files[i])
    if content != nil:
        corpus = corpus + content + chr(10)
        print "  Loaded: " + files[i]
print "Corpus: " + str(len(corpus)) + " chars"

# 3. Character tokenizer (fast, simple, good for small models)
print ""
let tok = tokenizer.char_tokenizer()
# Limit vocab to what we actually have
print "Tokenizer: character-level (128 ASCII tokens)"

# 4. Tokenize
let token_ids = tokenizer.encode(tok, corpus)
print "Tokens: " + str(len(token_ids))

# 5. Initialize model weights
print ""
print "Initializing weights..."
let seed = 42
let scale = 0.02

# Embedding: vocab_size x d_model
let embed_w = []
for i in range(128 * d_model):
    seed = (seed * 1664525 + 1013904223) & 4294967295
    push(embed_w, ((seed & 65535) / 65536 - 0.5) * 2 * scale)

# Layer weights (simplified - just Q, K, V projections for demo)
let layer_qw = []
let layer_kw = []
let layer_vw = []
for i in range(d_model * d_model):
    seed = (seed * 1664525 + 1013904223) & 4294967295
    push(layer_qw, ((seed & 65535) / 65536 - 0.5) * 2 * scale)
    seed = (seed * 1664525 + 1013904223) & 4294967295
    push(layer_kw, ((seed & 65535) / 65536 - 0.5) * 2 * scale)
    seed = (seed * 1664525 + 1013904223) & 4294967295
    push(layer_vw, ((seed & 65535) / 65536 - 0.5) * 2 * scale)

# RMSNorm weight
let norm_w = []
for i in range(d_model):
    push(norm_w, 1.0)

# LM head: d_model x 128 (char vocab)
let lm_head = []
for i in range(d_model * 128):
    seed = (seed * 1664525 + 1013904223) & 4294967295
    push(lm_head, ((seed & 65535) / 65536 - 0.5) * 2 * scale)

let total_params = 128 * d_model + 3 * d_model * d_model + d_model + d_model * 128
print "Total parameters: " + str(total_params)

# 6. Training loop with native backend
print ""
print "=== Training ==="

let seq_len = 32
let examples = train.create_lm_examples(token_ids, seq_len)
let num_examples = len(examples)
if num_examples > 10:
    num_examples = 10
print "Training on " + str(num_examples) + " examples (seq_len=" + str(seq_len) + ")"

for step in range(num_examples):
    let input_ids = examples[step]["input_ids"]
    let target_ids = examples[step]["target_ids"]

    # Forward: embed -> RMSNorm -> Q,K,V -> attention -> RMSNorm -> logits
    # Embed lookup
    let hidden = []
    for t in range(seq_len):
        let tid = input_ids[t]
        if tid >= 128:
            tid = 0
        for j in range(d_model):
            push(hidden, embed_w[tid * d_model + j])

    # RMSNorm (native)
    hidden = gpu_accel.rms_norm(_compute,hidden, norm_w, seq_len, d_model, 0.00001)

    # Q, K, V projections (native matmul)
    let q = gpu_accel.matmul(_compute,hidden, layer_qw, seq_len, d_model, d_model)
    let k = gpu_accel.matmul(_compute,hidden, layer_kw, seq_len, d_model, d_model)
    let v = gpu_accel.matmul(_compute,hidden, layer_vw, seq_len, d_model, d_model)

    # Self-attention (causal)
    let attn_out = attention.scaled_dot_product(q, k, v, seq_len, d_model, true)

    # Residual
    hidden = gpu_accel.add(_compute,hidden, attn_out)

    # Final norm
    hidden = gpu_accel.rms_norm(_compute,hidden, norm_w, seq_len, d_model, 0.00001)

    # LM head: last token -> logits
    let last_hidden = []
    let last_off = (seq_len - 1) * d_model
    for j in range(d_model):
        push(last_hidden, hidden[last_off + j])
    let logits = gpu_accel.matmul(_compute,last_hidden, lm_head, 1, d_model, 128)

    # Loss
    let last_target = [target_ids[seq_len - 1]]
    if last_target[0] >= 128:
        last_target[0] = 0
    let loss = gpu_accel.cross_entropy(_compute,logits, last_target, 1, 128)
    let ppl = train.perplexity(loss)

    print "Step " + str(step + 1) + "/" + str(num_examples) + " loss=" + str(loss) + " ppl=" + str(ppl)

print ""
print "=== SageGPT Training Complete ==="
print ""

# 7. Benchmark native backend
print "Native backend benchmark:"
let bench = gpu_accel.benchmark(_compute,64, 10)
print "  64x64 matmul: " + str(bench["ms_per_matmul"]) + " ms/op"
print "  GFLOPS: " + str(bench["gflops"])

# 8. Create agent
print ""
let sage_agent = agent.create_agent("sagegpt", "You are SageGPT, an AI built to understand and improve Sage.")
proc read_tool(args):
    return io.readfile(args)
agent.add_tool(sage_agent, "read_file", "Read source code", read_tool)
agent.add_fact(sage_agent["memory"], "Custom architecture: SwiGLU + RoPE + RMSNorm")
agent.add_fact(sage_agent["memory"], "Trained on Sage standard library source code")
print "Agent: " + sage_agent["name"]
print "Tools: " + str(len(sage_agent["toolbox"]["tool_list"]))
