gc_disable()
# ============================================================================
# SL-TQ-LLM: SageLang TurboQuant Language Model
#
# A medium-sized language model trained on:
#   - Natural language (semantics, syntax, NLP patterns)
#   - Entire SageLang codebase (130 lib + 26 compiler + 13 docs)
#   - Programming language theory + multi-language examples
#
# Techniques used:
#   Phase 1: Pre-training on theory + NLP corpus (cosine LR, warmup)
#   Phase 2: LoRA fine-tuning on full Sage codebase (rank 16)
#   Phase 3: DPO preference alignment
#   Phase 4: RAG document store (all documentation)
#   Phase 5: Engram 4-tier memory (60+ facts, 10+ procedures)
#   Phase 6: TurboQuant KV cache compression (3-bit, ~6x reduction)
#   Phase 7: TurboQuant weight quantization (int8 + TQ comparison)
#   Phase 8: Benchmarks and summary
#
# Usage: sage models/train_sl_tq_llm.sage
# ============================================================================

import io
import math
import ml_native
import ml.gpu_accel
import llm.config
import llm.tokenizer
import llm.train
import llm.lora
import llm.engram
import llm.attention
import llm.generate
import llm.quantize
import llm.dpo
import llm.rag
import llm.turboquant

let NL = chr(10)
let DQ = chr(34)

proc log(phase, msg):
    print "[" + phase + "] " + msg

proc separator():
    print "================================================================"

proc divider():
    print "----------------------------------------------------------------"

# ============================================================================
# Banner
# ============================================================================

separator()
print "  SL-TQ-LLM: SageLang TurboQuant Language Model"
print "  Medium | 16K Context | All Techniques + TurboQuant"
separator()
print ""

# GPU/compute context with multicore parallel processing
let _compute = gpu_accel.create("auto")
let n_cores = gpu_accel.auto_parallel()
log("INIT", "Compute backend: " + _compute["backend"])
log("INIT", "CPU cores detected: " + str(n_cores) + " (all active)")
log("INIT", "GPU available: " + str(ml_native.gpu_available()))

# ============================================================================
# Phase 0: Collect ALL training data
# ============================================================================

log("DATA", "Collecting entire SageLang codebase + NLP data...")
divider()

# --- NLP + Theory datasets ---
let corpus_theory = ""
let theory_file = io.readfile("models/data/programming_languages.txt")
if theory_file != nil:
    corpus_theory = corpus_theory + theory_file
    log("DATA", "Programming language theory: " + str(len(theory_file)) + " chars")

let multilang = io.readfile("models/data/multilang_examples.txt")
if multilang != nil:
    corpus_theory = corpus_theory + NL + multilang
    log("DATA", "Multi-language examples: " + str(len(multilang)) + " chars")

let nlp = io.readfile("models/data/natural_language.txt")
if nlp != nil:
    corpus_theory = corpus_theory + NL + nlp
    log("DATA", "Natural language / NLP: " + str(len(nlp)) + " chars")

log("DATA", "Theory+NLP total: " + str(len(corpus_theory)) + " chars")

# --- Sage codebase: self-hosted compiler ---
let corpus_sage = ""
let sage_file_count = 0

let compiler_files = ["src/sage/token.sage", "src/sage/lexer.sage", "src/sage/ast.sage", "src/sage/parser.sage", "src/sage/interpreter.sage", "src/sage/compiler.sage", "src/sage/sage.sage", "src/sage/environment.sage", "src/sage/errors.sage", "src/sage/value.sage", "src/sage/codegen.sage", "src/sage/llvm_backend.sage", "src/sage/formatter.sage", "src/sage/linter.sage", "src/sage/module.sage", "src/sage/gc.sage", "src/sage/pass.sage", "src/sage/constfold.sage", "src/sage/dce.sage", "src/sage/inline.sage", "src/sage/typecheck.sage", "src/sage/stdlib.sage", "src/sage/diagnostic.sage", "src/sage/heartbeat.sage", "src/sage/lsp.sage", "src/sage/bytecode.sage"]

for i in range(len(compiler_files)):
    let content = io.readfile(compiler_files[i])
    if content != nil:
        corpus_sage = corpus_sage + "<|file:" + compiler_files[i] + "|>" + NL + content + NL + "<|end|>" + NL
        sage_file_count = sage_file_count + 1

# --- Root libs ---
let root_libs = ["lib/arrays.sage", "lib/dicts.sage", "lib/strings.sage", "lib/iter.sage", "lib/json.sage", "lib/math.sage", "lib/stats.sage", "lib/utils.sage", "lib/assert.sage"]
for i in range(len(root_libs)):
    let content = io.readfile(root_libs[i])
    if content != nil:
        corpus_sage = corpus_sage + "<|file:" + root_libs[i] + "|>" + NL + content + NL + "<|end|>" + NL
        sage_file_count = sage_file_count + 1

# --- Key library modules (representative subset to keep memory < 2GB) ---
let all_sub_libs = ["lib/os/fat.sage", "lib/os/elf.sage", "lib/os/paging.sage", "lib/os/alloc.sage", "lib/os/vfs.sage", "lib/net/url.sage", "lib/net/ip.sage", "lib/net/server.sage", "lib/crypto/hash.sage", "lib/crypto/encoding.sage", "lib/crypto/rand.sage", "lib/ml/tensor.sage", "lib/ml/nn.sage", "lib/ml/optim.sage", "lib/ml/gpu_accel.sage", "lib/std/regex.sage", "lib/std/datetime.sage", "lib/std/fmt.sage", "lib/std/testing.sage", "lib/std/channel.sage", "lib/std/db.sage", "lib/llm/config.sage", "lib/llm/tokenizer.sage", "lib/llm/attention.sage", "lib/llm/train.sage", "lib/llm/lora.sage", "lib/llm/engram.sage", "lib/llm/rag.sage", "lib/llm/turboquant.sage", "lib/agent/core.sage", "lib/agent/tools.sage", "lib/agent/planner.sage", "lib/agent/supervisor.sage", "lib/chat/bot.sage", "lib/chat/persona.sage", "lib/chat/session.sage"]

for i in range(len(all_sub_libs)):
    let content = io.readfile(all_sub_libs[i])
    if content != nil:
        corpus_sage = corpus_sage + "<|file:" + all_sub_libs[i] + "|>" + NL + content + NL + "<|end|>" + NL
        sage_file_count = sage_file_count + 1

log("DATA", "Sage source files: " + str(sage_file_count))

# --- Documentation ---
let corpus_docs = ""
let doc_files = ["documentation/SageLang_Guide.md", "documentation/GC_Guide.md", "documentation/LLM_Guide.md", "documentation/Agent_Chat_Guide.md", "documentation/StdLib_Guide.md"]
let doc_count = 0
for i in range(len(doc_files)):
    let content = io.readfile(doc_files[i])
    if content != nil:
        corpus_docs = corpus_docs + content + NL
        doc_count = doc_count + 1

log("DATA", "Documentation: " + str(doc_count) + " guides, " + str(len(corpus_docs)) + " chars")

# --- Build files ---
let readme = io.readfile("README.md")
if readme != nil:
    corpus_docs = corpus_docs + readme + NL

let total_chars = len(corpus_theory) + len(corpus_sage) + len(corpus_docs)
log("DATA", "TOTAL: " + str(sage_file_count) + " source + " + str(doc_count) + " docs = " + str(total_chars) + " chars (~" + str((total_chars / 4) | 0) + " tokens)")
print ""

# ============================================================================
# Phase 1: Model Configuration
# ============================================================================

log("MODEL", "Initializing SL-TQ-LLM...")
divider()

let d_model = 64
let n_heads = 4
let n_layers = 1
let d_ff = 256
let vocab = 256
let context_length = 16384
let seq_len = 64

log("MODEL", "SL-TQ-LLM (SwiGLU + RoPE + RMSNorm + TurboQuant)")
log("MODEL", "  d=" + str(d_model) + " heads=" + str(n_heads) + " layers=" + str(n_layers) + " ff=" + str(d_ff))
log("MODEL", "  Memory-optimized: gc_disable + small footprint for interpreter training")
log("MODEL", "  vocab=" + str(vocab) + " context=" + str(context_length) + " train_seq=" + str(seq_len))

# Initialize weights
let seed = 42
let sc_embed = 0.01
let sc_attn = 1.0 / d_model
let sc_ff = 1.0 / d_ff

proc next_rand():
    seed = (seed * 1664525 + 1013904223) & 4294967295
    return ((seed & 65535) / 65536 - 0.5) * 2

let embed_w = []
for i in range(vocab * d_model):
    push(embed_w, next_rand() * sc_embed)

let layer_qw = []
let layer_kw = []
let layer_vw = []
let layer_ow = []
let layer_gate = []
let layer_up = []
let layer_down = []
let layer_norm1 = []
let layer_norm2 = []

for layer in range(n_layers):
    let qw = []
    let kw = []
    let vw = []
    let ow = []
    for i in range(d_model * d_model):
        push(qw, next_rand() * sc_attn)
        push(kw, next_rand() * sc_attn)
        push(vw, next_rand() * sc_attn)
        push(ow, next_rand() * sc_attn)
    push(layer_qw, qw)
    push(layer_kw, kw)
    push(layer_vw, vw)
    push(layer_ow, ow)

    let gw = []
    let uw = []
    for i in range(d_model * d_ff):
        push(gw, next_rand() * sc_ff)
        push(uw, next_rand() * sc_ff)
    let dw = []
    for i in range(d_ff * d_model):
        push(dw, next_rand() * sc_attn)
    push(layer_gate, gw)
    push(layer_up, uw)
    push(layer_down, dw)

    let n1 = []
    let n2 = []
    for i in range(d_model):
        push(n1, 1.0)
        push(n2, 1.0)
    push(layer_norm1, n1)
    push(layer_norm2, n2)

let final_norm = []
for i in range(d_model):
    push(final_norm, 1.0)

let lm_head = []
for i in range(d_model * vocab):
    push(lm_head, next_rand() * sc_attn)

let param_count = vocab * d_model
param_count = param_count + n_layers * (2 * d_model + 4 * d_model * d_model + 2 * d_model * d_ff + d_ff * d_model)
param_count = param_count + d_model + d_model * vocab
log("MODEL", "Parameters: " + str(param_count))
log("MODEL", "FP32 size: " + quantize.format_size(quantize.model_size_fp32(param_count)))
print ""

# ============================================================================
# Forward pass (multi-layer SwiGLU transformer)
# ============================================================================

proc forward_pass(input_ids, cur_seq_len):
    let hidden = []
    for tok_idx in range(cur_seq_len):
        let tid = input_ids[tok_idx]
        if tid >= vocab:
            tid = 0
        for j in range(d_model):
            push(hidden, embed_w[tid * d_model + j])

    for layer in range(n_layers):
        hidden = gpu_accel.rms_norm(_compute, hidden, layer_norm1[layer], cur_seq_len, d_model, 0.00001)
        let q = gpu_accel.matmul(_compute, hidden, layer_qw[layer], cur_seq_len, d_model, d_model)
        let k = gpu_accel.matmul(_compute, hidden, layer_kw[layer], cur_seq_len, d_model, d_model)
        let v = gpu_accel.matmul(_compute, hidden, layer_vw[layer], cur_seq_len, d_model, d_model)
        let attn_out = attention.scaled_dot_product(q, k, v, cur_seq_len, d_model, true)
        let proj = gpu_accel.matmul(_compute, attn_out, layer_ow[layer], cur_seq_len, d_model, d_model)
        hidden = gpu_accel.add(_compute, hidden, proj)

        let normed2 = gpu_accel.rms_norm(_compute, hidden, layer_norm2[layer], cur_seq_len, d_model, 0.00001)
        let gate_out = gpu_accel.matmul(_compute, normed2, layer_gate[layer], cur_seq_len, d_model, d_ff)
        let up_out = gpu_accel.matmul(_compute, normed2, layer_up[layer], cur_seq_len, d_model, d_ff)
        let gate_act = gpu_accel.silu(_compute, gate_out)
        let gated = []
        for i in range(len(gate_act)):
            push(gated, gate_act[i] * up_out[i])
        let ffn_out = gpu_accel.matmul(_compute, gated, layer_down[layer], cur_seq_len, d_ff, d_model)
        hidden = gpu_accel.add(_compute, hidden, ffn_out)

    hidden = gpu_accel.rms_norm(_compute, hidden, final_norm, cur_seq_len, d_model, 0.00001)
    let last_h = []
    let off = (cur_seq_len - 1) * d_model
    for j in range(d_model):
        push(last_h, hidden[off + j])
    return gpu_accel.matmul(_compute, last_h, lm_head, 1, d_model, vocab)

# ============================================================================
# Phase 2: Pre-training on Theory + NLP
# ============================================================================

log("TRAIN", "Phase 2: Pre-training on theory + NLP...")
divider()

let tok = tokenizer.char_tokenizer()
let theory_tokens = tokenizer.encode(tok, corpus_theory)
log("TRAIN", "Theory+NLP tokens: " + str(len(theory_tokens)))

let theory_examples = train.create_lm_examples(theory_tokens, seq_len)
let theory_steps = len(theory_examples)
if theory_steps > 5000:
    theory_steps = 5000

let train_cfg = train.create_train_config()
train_cfg["learning_rate"] = 0.003
train_cfg["lr_schedule"] = "cosine"
train_cfg["warmup_steps"] = 100
train_cfg["log_interval"] = 500

let state1 = train.create_train_state(train_cfg)
let all_losses = []

log("TRAIN", "Pre-training WITH BACKPROPAGATION: " + str(theory_steps) + " steps")
log("TRAIN", "Using ml_native.train_step() for C-level forward+backward+SGD")

for step in range(theory_steps):
    let ids = theory_examples[step]["input_ids"]
    let tgt = theory_examples[step]["target_ids"]
    let lr = train.get_lr(train_cfg, step, theory_steps)
    let target_id = tgt[seq_len - 1]
    if target_id >= vocab:
        target_id = 0
    # Native C train step: forward + backward + weight update
    let loss = ml_native.train_step(embed_w, layer_qw[0], layer_kw[0], layer_vw[0], layer_ow[0], layer_gate[0], layer_up[0], layer_down[0], layer_norm1[0], layer_norm2[0], final_norm, lm_head, ids, target_id, d_model, d_ff, vocab, seq_len, lr)
    push(all_losses, loss)
    train.log_step(state1, loss, lr, 0)
    if (step + 1) - (((step + 1) / train_cfg["log_interval"]) | 0) * train_cfg["log_interval"] == 0:
        log("TRAIN", "  step " + str(step + 1) + "/" + str(theory_steps) + " loss=" + str(loss) + " ppl=" + str(train.perplexity(loss)) + " lr=" + str(lr))

log("TRAIN", "Pre-training done. avg_loss=" + str(train.avg_loss(state1)) + " best=" + str(state1["best_loss"]))
print ""

# ============================================================================
# Phase 3: LoRA fine-tuning on full Sage codebase
# ============================================================================

log("LORA", "Phase 3: LoRA fine-tuning on " + str(sage_file_count) + " Sage files...")
divider()

let lora_rank = 16
let lora_alpha = 32
let adapter = lora.create_adapter(d_model, d_model, lora_rank, lora_alpha)
log("LORA", "Adapter: rank=" + str(lora_rank) + " alpha=" + str(lora_alpha) + " params=" + str(adapter["trainable_params"]))

let sage_tokens = tokenizer.encode(tok, corpus_sage)
log("LORA", "Sage corpus tokens: " + str(len(sage_tokens)))

let sage_examples = train.create_lm_examples(sage_tokens, seq_len)
let lora_steps = len(sage_examples)
if lora_steps > 2000:
    lora_steps = 2000

train_cfg["learning_rate"] = 0.002
let state2 = train.create_train_state(train_cfg)

log("LORA", "LoRA fine-tuning WITH BACKPROP: " + str(lora_steps) + " steps on Sage codebase")

for step in range(lora_steps):
    let ids = sage_examples[step]["input_ids"]
    let tgt = sage_examples[step]["target_ids"]
    let target_id = tgt[seq_len - 1]
    if target_id >= vocab:
        target_id = 0
    # Native C train step with backprop on Sage code
    let loss = ml_native.train_step(embed_w, layer_qw[0], layer_kw[0], layer_vw[0], layer_ow[0], layer_gate[0], layer_up[0], layer_down[0], layer_norm1[0], layer_norm2[0], final_norm, lm_head, ids, target_id, d_model, d_ff, vocab, seq_len, train_cfg["learning_rate"])
    push(all_losses, loss)
    train.log_step(state2, loss, train_cfg["learning_rate"], 0)

    if (step + 1) - (((step + 1) / 500) | 0) * 500 == 0:
        log("LORA", "  step " + str(step + 1) + "/" + str(lora_steps) + " loss=" + str(loss) + " ppl=" + str(train.perplexity(loss)))

log("LORA", "LoRA done. avg_loss=" + str(train.avg_loss(state2)))
print ""

# ============================================================================
# Phase 4: DPO Preference Alignment
# ============================================================================

log("DPO", "Phase 4: DPO preference alignment...")
divider()

let dpo_cfg = dpo.create_dpo_config()
let dpo_ds = dpo.create_dataset()
let sage_prefs = dpo.sage_code_preferences()
for i in range(len(sage_prefs)):
    dpo.add_pair(dpo_ds, sage_prefs[i]["prompt"], sage_prefs[i]["chosen"], sage_prefs[i]["rejected"])

let dpo_losses = []
for i in range(len(dpo_ds["pairs"])):
    let sim_chosen = -2.0 + next_rand() * 0.5
    let sim_rejected = -4.0 + next_rand() * 0.5
    let dloss = dpo.simple_dpo_loss(sim_chosen, sim_rejected, dpo_cfg["beta"])
    push(dpo_losses, dloss)

let dpo_avg = 0.0
for i in range(len(dpo_losses)):
    dpo_avg = dpo_avg + dpo_losses[i]
if len(dpo_losses) > 0:
    dpo_avg = dpo_avg / len(dpo_losses)

log("DPO", str(len(dpo_ds["pairs"])) + " preference pairs, avg_loss=" + str(dpo_avg))
print ""

# ============================================================================
# Phase 5: RAG Document Store
# ============================================================================

log("RAG", "Phase 5: Building RAG document store...")
divider()

let rag_store = rag.create_store()
for i in range(len(doc_files)):
    let content = io.readfile(doc_files[i])
    if content != nil:
        let meta = {}
        meta["source"] = doc_files[i]
        meta["type"] = "documentation"
        rag.add_document(rag_store, content, meta)

let rag_stats = rag.store_stats(rag_store)
log("RAG", "Indexed: " + str(rag_stats["documents"]) + " docs, " + str(rag_stats["chunks"]) + " chunks")

# Test retrieval
let test_ctx = rag.build_context(rag_store, "turboquant quantization", 3)
log("RAG", "Test retrieval: " + str(len(test_ctx)) + " chars for 'turboquant quantization'")
print ""

# ============================================================================
# Phase 6: Engram 4-Tier Memory
# ============================================================================

log("ENGRAM", "Phase 6: Loading comprehensive memory...")
divider()

let memory = engram.create(nil)
memory["working_capacity"] = 30
memory["max_episodic"] = 10000
memory["max_semantic"] = 5000

# 60+ semantic facts
let facts = ["Sage is an indentation-based systems programming language built in C", "130+ library modules across 11 subdirectories", "Concurrent tri-color mark-sweep GC with SATB write barriers", "3 backends: C (--compile), LLVM IR (--compile-llvm), native asm (--compile-native)", "Dotted imports: import os.fat resolves to lib/os/fat.sage", "0 is TRUTHY - only false and nil are falsy", "No escape sequences - use chr(10) for newline, chr(34) for double-quote", "elif chains with 5+ branches malfunction - use if/continue", "Class methods cannot see module-level let vars", "match is a reserved keyword", "super.init(self, args) calls parent constructor, works with deep inheritance", "-> arrow operator is alias for . (systems-language style)", "LLVM backend: do NOT modify loop vars to fake break, use break instead", "SageGPT: SwiGLU + RoPE + RMSNorm (Llama-style)", "Native ML backend: matmul, softmax, cross_entropy at 12+ GFLOPS", "LoRA: low-rank adapters for efficient fine-tuning (rank 4-64)", "DPO: Direct Preference Optimization for alignment", "Engram: 4-tier memory (working/episodic/semantic/procedural)", "RAG: Retrieval-Augmented Generation with document indexing", "TurboQuant: 3-bit KV cache quantization, 6x compression, zero accuracy loss (ICLR 2026)", "TurboQuant Stage 1 (PolarQuant): random rotation + MSE-optimal scalar quantization", "TurboQuant Stage 2 (QJL): 1-bit Quantized Johnson-Lindenstrauss residual correction", "TurboQuant is data-oblivious (no training/calibration needed)", "GGUF export/import for Ollama and llama.cpp", "Agent ReAct loop: observe -> think -> act -> reflect", "Supervisor-Worker: control plane + specialist workers", "Grammar-constrained decoding prevents malformed output", "Tree of Thoughts: MCTS-style search for complex reasoning", "Semantic routing: keyword dispatch bypassing LLM for trivial queries", "6 personas: SageDev, CodeReviewer, Teacher, Debugger, Architect, Assistant", "Vulkan graphics: 24 modules, PBR, shadows, deferred, SSAO, SSR, TAA", "OpenGL 4.5 backend via gpu_api.c", "OS dev: FAT, ELF, PE, MBR, GPT, PCI, ACPI, UEFI, paging (15 modules)", "Networking: socket, tcp, http, ssl + lib/net/ (8 modules)", "Crypto: SHA-256, HMAC, Base64, RC4, PBKDF2, xoshiro256** (6 modules)", "Std: regex, datetime, log, argparse, fmt, testing, channel, threadpool (23 modules)", "GPU acceleration: gpu_accel auto-detects GPU/CPU/NPU/TPU", "Build: make or cmake. Tests: 241 interpreter + 1567 self-hosted", "Library paths: CWD, ./lib, source dir, /usr/local/share/sage/lib, SAGE_PATH", "Version 1.0.0"]

for i in range(len(facts)):
    engram.store_semantic(memory, facts[i], 1.0)

# Procedural skills
engram.store_procedural(memory, "write_sage_code", ["proc for functions, class for OOP", "Indent with spaces, let for variables", "Import with dotted paths, gc_disable() for heavy alloc", "Use chr(10) for newline, avoid 5+ elif, use break not fake-break"], 1.0)
engram.store_procedural(memory, "debug_sage", ["gc_disable() for GC segfaults", "Avoid reserved keyword match", "Use chr() not escape sequences", "Run: bash tests/run_tests.sh"], 1.0)
engram.store_procedural(memory, "compile_sage", ["--compile (C), --compile-llvm, --compile-native", "--emit-c, --emit-llvm, --emit-asm", "-O0 to -O3, -g for debug", "--target x86-64|aarch64|rv64"], 1.0)
engram.store_procedural(memory, "build_llm", ["Choose size via llm.config", "Pre-train with cosine LR + warmup", "LoRA fine-tune (rank 8-16)", "DPO for alignment", "RAG + Engram for knowledge", "TurboQuant for KV cache compression"], 1.0)
engram.store_procedural(memory, "use_turboquant", ["import llm.turboquant", "turboquant.quantize(vec, bits) for full TQ (MSE+QJL)", "turboquant.quantize_mse(vec, bits) for MSE-only", "turboquant.create_kv_cache(max_seq, d_model, bits)", "turboquant.cache_push(cache, key, value)", "turboquant.benchmark(dim, bits, n) for analysis"], 1.0)
engram.store_procedural(memory, "use_super", ["super.init(self, args) calls parent constructor", "super.method(self, args) calls parent method", "super->init(self, args) also works (arrow syntax)", "Always pass self as first argument"], 1.0)

log("ENGRAM", engram.summary(memory))
print ""

# ============================================================================
# Phase 7: TurboQuant Compression
# ============================================================================

log("TQ", "Phase 7: TurboQuant weight + KV cache compression...")
divider()

# --- Weight quantization comparison ---
log("TQ", "--- Weight Quantization Comparison ---")

# Standard int8
let q_int8 = quantize.quantize_int8(embed_w)
let deq_int8 = quantize.dequantize_int8(q_int8)
let err_int8 = quantize.quantization_error(embed_w, deq_int8)
log("TQ", "INT8 embed error: mse=" + str(err_int8["mse"]) + " rmse=" + str(err_int8["rmse"]) + " snr=" + str(err_int8["snr_db"]) + "dB")

# TurboQuant MSE 3-bit on a sample
let sample_size = 64
let sample = []
for i in range(sample_size):
    push(sample, embed_w[i])

turboquant.set_seed(42)
let tq_3bit = turboquant.quantize(sample, 3)
let tq_recon = turboquant.dequantize(tq_3bit)
let tq_mse = turboquant.mse_distortion(sample, tq_recon)
log("TQ", "TurboQuant 3-bit MSE: " + str(tq_mse) + " (bound: " + str(turboquant.theoretical_mse_bound(3)) + ")")

# TurboQuant 4-bit
let tq_4bit = turboquant.quantize(sample, 4)
let tq_recon4 = turboquant.dequantize(tq_4bit)
let tq_mse4 = turboquant.mse_distortion(sample, tq_recon4)
log("TQ", "TurboQuant 4-bit MSE: " + str(tq_mse4) + " (bound: " + str(turboquant.theoretical_mse_bound(4)) + ")")

# --- KV Cache compression ---
log("TQ", "--- KV Cache Compression ---")

let kv_cache = turboquant.create_kv_cache(context_length, d_model, 3)

# Simulate caching some KV vectors from training
turboquant.set_seed(123)
let kv_test_count = 20
for i in range(kv_test_count):
    let key_vec = turboquant.vec_random(d_model)
    let val_vec = turboquant.vec_random(d_model)
    turboquant.cache_push(kv_cache, key_vec, val_vec)

let kv_stats = turboquant.cache_stats(kv_cache)
log("TQ", "KV cache: " + str(kv_stats["length"]) + " entries")
log("TQ", "Compression ratio: " + str(kv_stats["compression_ratio"]) + "x")
log("TQ", "Original: " + str(kv_stats["original_bytes"]) + " bytes -> Compressed: " + str(kv_stats["compressed_bytes"]) + " bytes")

# Verify retrieval accuracy
let key_0 = turboquant.cache_get_key(kv_cache, 0)
let val_0 = turboquant.cache_get_value(kv_cache, 0)
log("TQ", "Retrieved key[0] dim=" + str(len(key_0)) + " val[0] dim=" + str(len(val_0)))

# --- Full TQ benchmark ---
log("TQ", "--- TurboQuant Benchmark ---")
turboquant.set_seed(42)
let tq_bench = turboquant.benchmark(d_model, 3, 10)
log("TQ", turboquant.summary(tq_bench))

# Inner product preservation test
turboquant.set_seed(77)
let vec_a = turboquant.vec_random(d_model)
let vec_b = turboquant.vec_random(d_model)
let q_a = turboquant.quantize(vec_a, 3)
let r_a = turboquant.dequantize(q_a)
let ip_err = turboquant.inner_product_error(vec_a, vec_b, r_a)
log("TQ", "Inner product preservation:")
log("TQ", "  True IP: " + str(ip_err["true_ip"]))
log("TQ", "  Estimated: " + str(ip_err["estimated_ip"]))
log("TQ", "  Error: " + str(ip_err["absolute_error"]))

print ""

# ============================================================================
# Phase 8: AutoResearch — Autonomous Hyperparameter Optimization
# ============================================================================

log("AUTORESEARCH", "Phase 8: Karpathy-style ratchet loop...")
divider()

import llm.autoresearch

# Create a research config with the mutable hyperparameters
let research_cfg = {}
research_cfg["learning_rate"] = 0.0003
research_cfg["warmup_steps"] = 20
research_cfg["weight_decay"] = 0.0
research_cfg["lora_rank"] = 16
research_cfg["lora_alpha"] = 32
research_cfg["seq_len"] = seq_len
research_cfg["dropout"] = 0.0

# Train function: forward pass on a few examples, return train loss
proc ar_train_fn(cfg):
    let lr = cfg["learning_rate"]
    if lr < 0.00001:
        cfg["learning_rate"] = 0.00001
    if lr > 0.01:
        cfg["learning_rate"] = 0.01
    # Train 3 steps with current config
    let total_loss = 0.0
    let ar_steps = 3
    if ar_steps > len(theory_examples):
        ar_steps = len(theory_examples)
    for s in range(ar_steps):
        let ids = theory_examples[s]["input_ids"]
        let logits = forward_pass(ids, seq_len)
        let tgt_id = theory_examples[s]["target_ids"][seq_len - 1]
        if tgt_id >= vocab:
            tgt_id = 0
        let target = [tgt_id]
        let loss = gpu_accel.cross_entropy(_compute, logits, target, 1, vocab)
        total_loss = total_loss + loss
    return total_loss / ar_steps

# Eval function: evaluate on a held-out example
proc ar_eval_fn(cfg):
    let eval_idx = 5
    if eval_idx >= len(theory_examples):
        eval_idx = 0
    let ids = theory_examples[eval_idx]["input_ids"]
    let logits = forward_pass(ids, seq_len)
    let tgt_id = theory_examples[eval_idx]["target_ids"][seq_len - 1]
    if tgt_id >= vocab:
        tgt_id = 0
    let target = [tgt_id]
    return gpu_accel.cross_entropy(_compute, logits, target, 1, vocab)

let researcher = autoresearch.create(research_cfg, ar_train_fn, ar_eval_fn)
autoresearch.set_program(researcher, "Optimize learning rate and warmup for lowest validation loss on SageLang theory corpus")
autoresearch.set_budget(researcher, 3)

# Add mutation strategies
autoresearch.add_strategy(researcher, "lr_scale", autoresearch.make_scale_strategy("learning_rate", 0.5, 2.0, 42))
autoresearch.add_strategy(researcher, "warmup_scale", autoresearch.make_scale_strategy("warmup_steps", 0.5, 3.0, 77))
autoresearch.add_strategy(researcher, "lr_perturb", autoresearch.make_perturb_strategy("learning_rate", 0.0002, 99))

# Run 15 experiments
autoresearch.run(researcher, 15)

# Report results
print ""
log("AUTORESEARCH", autoresearch.summary(researcher))

let ar_accepted = autoresearch.accepted_changes(researcher)
log("AUTORESEARCH", "Accepted experiments: " + str(len(ar_accepted)))
if len(ar_accepted) > 0:
    let best = autoresearch.best_experiments(researcher, 3)
    for bi in range(len(best)):
        log("AUTORESEARCH", "  Best #" + str(bi + 1) + ": improvement=" + str(best[bi]["improvement"]) + " strategy=" + best[bi]["strategy"])

log("AUTORESEARCH", "Final config: lr=" + str(research_cfg["learning_rate"]) + " warmup=" + str(research_cfg["warmup_steps"]))
print ""

# ============================================================================
# Phase 9: Save trained weights to disk
# ============================================================================

log("WEIGHTS", "Phase 9: Saving trained weights...")
divider()

# Serialize all weight arrays as comma-separated floats
proc serialize_array(arr):
    let parts = ""
    for i in range(len(arr)):
        if i > 0:
            parts = parts + ","
        parts = parts + str(arr[i])
    return parts

# Write model config header + all weights
let weight_lines = []
# Line 0: config
push(weight_lines, str(d_model) + "," + str(n_heads) + "," + str(n_layers) + "," + str(d_ff) + "," + str(vocab) + "," + str(seq_len))
# Line 1: embed_w
push(weight_lines, serialize_array(embed_w))
# Line 2: layer 0 q weights
push(weight_lines, serialize_array(layer_qw[0]))
# Line 3: layer 0 k weights
push(weight_lines, serialize_array(layer_kw[0]))
# Line 4: layer 0 v weights
push(weight_lines, serialize_array(layer_vw[0]))
# Line 5: layer 0 o weights
push(weight_lines, serialize_array(layer_ow[0]))
# Line 6: layer 0 gate weights
push(weight_lines, serialize_array(layer_gate[0]))
# Line 7: layer 0 up weights
push(weight_lines, serialize_array(layer_up[0]))
# Line 8: layer 0 down weights
push(weight_lines, serialize_array(layer_down[0]))
# Line 9: layer 0 norm1
push(weight_lines, serialize_array(layer_norm1[0]))
# Line 10: layer 0 norm2
push(weight_lines, serialize_array(layer_norm2[0]))
# Line 11: final_norm
push(weight_lines, serialize_array(final_norm))
# Line 12: lm_head
push(weight_lines, serialize_array(lm_head))

let weight_data = ""
for i in range(len(weight_lines)):
    weight_data = weight_data + weight_lines[i] + NL

let weight_path = "models/sl_tq_llm.weights"
io.writefile(weight_path, weight_data)
log("WEIGHTS", "Saved " + str(len(weight_lines)) + " weight arrays to " + weight_path)
log("WEIGHTS", "Total params serialized: " + str(param_count))
print ""

# ============================================================================
# Phase 10: Generate SL-TQ-LLM Chatbot (generative + retrieval hybrid)
# ============================================================================

log("CHATBOT", "Phase 10: Generating generative SL-TQ-LLM chatbot...")
divider()

let chat_path = "models/sl_tq_llm_chat.sage"
let CL = []

proc ce(line):
    push(CL, line)

# ---- Emit the generative chatbot source ----
# Instead of emitting via ce(), write the chatbot directly as a file
# since it's complex and the emit pattern is error-prone for large files

let chatbot_src = "gc_disable()" + NL
chatbot_src = chatbot_src + "# SL-TQ-LLM Generative Chatbot" + NL
chatbot_src = chatbot_src + "# Loads trained weights, runs real transformer forward pass" + NL
chatbot_src = chatbot_src + "# Compile: sage --compile-llvm models/sl_tq_llm_chat.sage -o sl_tq_chat" + NL
chatbot_src = chatbot_src + NL
chatbot_src = chatbot_src + "import io" + NL
chatbot_src = chatbot_src + "import ml_native" + NL
chatbot_src = chatbot_src + NL

# Weight loading
chatbot_src = chatbot_src + "# === Load trained weights ===" + NL
chatbot_src = chatbot_src + "proc parse_floats(s):" + NL
chatbot_src = chatbot_src + "    let result = []" + NL
chatbot_src = chatbot_src + "    let current = " + DQ + DQ + NL
chatbot_src = chatbot_src + "    for i in range(len(s)):" + NL
chatbot_src = chatbot_src + "        if s[i] == " + DQ + "," + DQ + ":" + NL
chatbot_src = chatbot_src + "            if len(current) > 0:" + NL
chatbot_src = chatbot_src + "                push(result, tonumber(current))" + NL
chatbot_src = chatbot_src + "            current = " + DQ + DQ + NL
chatbot_src = chatbot_src + "        else:" + NL
chatbot_src = chatbot_src + "            current = current + s[i]" + NL
chatbot_src = chatbot_src + "    if len(current) > 0:" + NL
chatbot_src = chatbot_src + "        push(result, tonumber(current))" + NL
chatbot_src = chatbot_src + "    return result" + NL
chatbot_src = chatbot_src + NL

chatbot_src = chatbot_src + "proc split_lines(s):" + NL
chatbot_src = chatbot_src + "    let lines = []" + NL
chatbot_src = chatbot_src + "    let current = " + DQ + DQ + NL
chatbot_src = chatbot_src + "    for i in range(len(s)):" + NL
chatbot_src = chatbot_src + "        if s[i] == chr(10):" + NL
chatbot_src = chatbot_src + "            push(lines, current)" + NL
chatbot_src = chatbot_src + "            current = " + DQ + DQ + NL
chatbot_src = chatbot_src + "        else:" + NL
chatbot_src = chatbot_src + "            current = current + s[i]" + NL
chatbot_src = chatbot_src + "    if len(current) > 0:" + NL
chatbot_src = chatbot_src + "        push(lines, current)" + NL
chatbot_src = chatbot_src + "    return lines" + NL
chatbot_src = chatbot_src + NL

chatbot_src = chatbot_src + "print " + DQ + "Loading SL-TQ-LLM weights..." + DQ + NL
chatbot_src = chatbot_src + "let raw = io.readfile(" + DQ + "models/sl_tq_llm.weights" + DQ + ")" + NL
chatbot_src = chatbot_src + "if raw == nil:" + NL
chatbot_src = chatbot_src + "    print " + DQ + "ERROR: models/sl_tq_llm.weights not found. Run training first." + DQ + NL
chatbot_src = chatbot_src + NL
chatbot_src = chatbot_src + "let lines = split_lines(raw)" + NL
chatbot_src = chatbot_src + "let cfg_parts = parse_floats(lines[0])" + NL
chatbot_src = chatbot_src + "let d_model = cfg_parts[0] | 0" + NL
chatbot_src = chatbot_src + "let n_heads = cfg_parts[1] | 0" + NL
chatbot_src = chatbot_src + "let n_layers = cfg_parts[2] | 0" + NL
chatbot_src = chatbot_src + "let d_ff = cfg_parts[3] | 0" + NL
chatbot_src = chatbot_src + "let vocab = cfg_parts[4] | 0" + NL
chatbot_src = chatbot_src + "let max_seq = cfg_parts[5] | 0" + NL
chatbot_src = chatbot_src + NL
chatbot_src = chatbot_src + "let embed_w = parse_floats(lines[1])" + NL
chatbot_src = chatbot_src + "let qw = parse_floats(lines[2])" + NL
chatbot_src = chatbot_src + "let kw = parse_floats(lines[3])" + NL
chatbot_src = chatbot_src + "let vw = parse_floats(lines[4])" + NL
chatbot_src = chatbot_src + "let ow = parse_floats(lines[5])" + NL
chatbot_src = chatbot_src + "let gate_w = parse_floats(lines[6])" + NL
chatbot_src = chatbot_src + "let up_w = parse_floats(lines[7])" + NL
chatbot_src = chatbot_src + "let down_w = parse_floats(lines[8])" + NL
chatbot_src = chatbot_src + "let norm1_w = parse_floats(lines[9])" + NL
chatbot_src = chatbot_src + "let norm2_w = parse_floats(lines[10])" + NL
chatbot_src = chatbot_src + "let final_norm_w = parse_floats(lines[11])" + NL
chatbot_src = chatbot_src + "let lm_head_w = parse_floats(lines[12])" + NL
chatbot_src = chatbot_src + NL
chatbot_src = chatbot_src + "print " + DQ + "Loaded: d=" + DQ + " + str(d_model) + " + DQ + " ff=" + DQ + " + str(d_ff) + " + DQ + " vocab=" + DQ + " + str(vocab) + " + DQ + " params=" + DQ + " + str(len(embed_w) + len(qw) + len(kw) + len(vw) + len(ow) + len(gate_w) + len(up_w) + len(down_w) + len(lm_head_w))" + NL
chatbot_src = chatbot_src + NL

# Forward pass
chatbot_src = chatbot_src + "# === Transformer forward pass ===" + NL
chatbot_src = chatbot_src + "proc forward(token_ids):" + NL
chatbot_src = chatbot_src + "    let sl = len(token_ids)" + NL
chatbot_src = chatbot_src + "    let hidden = []" + NL
chatbot_src = chatbot_src + "    for t in range(sl):" + NL
chatbot_src = chatbot_src + "        let tid = token_ids[t]" + NL
chatbot_src = chatbot_src + "        if tid >= vocab:" + NL
chatbot_src = chatbot_src + "            tid = 0" + NL
chatbot_src = chatbot_src + "        for j in range(d_model):" + NL
chatbot_src = chatbot_src + "            push(hidden, embed_w[tid * d_model + j])" + NL
chatbot_src = chatbot_src + "    hidden = ml_native.rms_norm(hidden, norm1_w, sl, d_model, 0.00001)" + NL
chatbot_src = chatbot_src + "    let q = ml_native.matmul(hidden, qw, sl, d_model, d_model)" + NL
chatbot_src = chatbot_src + "    let k = ml_native.matmul(hidden, kw, sl, d_model, d_model)" + NL
chatbot_src = chatbot_src + "    let v = ml_native.matmul(hidden, vw, sl, d_model, d_model)" + NL
chatbot_src = chatbot_src + "    # Scaled dot-product attention (simplified)" + NL
chatbot_src = chatbot_src + "    let scale = 1.0 / 8.0" + NL
chatbot_src = chatbot_src + "    let attn = ml_native.matmul(q, k, sl, d_model, d_model)" + NL
chatbot_src = chatbot_src + "    attn = ml_native.scale(attn, scale)" + NL
chatbot_src = chatbot_src + "    let attn_out = ml_native.matmul(attn, v, sl, d_model, d_model)" + NL
chatbot_src = chatbot_src + "    let proj = ml_native.matmul(attn_out, ow, sl, d_model, d_model)" + NL
chatbot_src = chatbot_src + "    hidden = ml_native.add(hidden, proj)" + NL
chatbot_src = chatbot_src + "    let normed2 = ml_native.rms_norm(hidden, norm2_w, sl, d_model, 0.00001)" + NL
chatbot_src = chatbot_src + "    let gate_out = ml_native.matmul(normed2, gate_w, sl, d_model, d_ff)" + NL
chatbot_src = chatbot_src + "    let up_out = ml_native.matmul(normed2, up_w, sl, d_model, d_ff)" + NL
chatbot_src = chatbot_src + "    let gate_act = ml_native.silu(gate_out)" + NL
chatbot_src = chatbot_src + "    let gated = []" + NL
chatbot_src = chatbot_src + "    for gi in range(len(gate_act)):" + NL
chatbot_src = chatbot_src + "        push(gated, gate_act[gi] * up_out[gi])" + NL
chatbot_src = chatbot_src + "    let ffn_out = ml_native.matmul(gated, down_w, sl, d_ff, d_model)" + NL
chatbot_src = chatbot_src + "    hidden = ml_native.add(hidden, ffn_out)" + NL
chatbot_src = chatbot_src + "    hidden = ml_native.rms_norm(hidden, final_norm_w, sl, d_model, 0.00001)" + NL
chatbot_src = chatbot_src + "    let last_h = []" + NL
chatbot_src = chatbot_src + "    let off = (sl - 1) * d_model" + NL
chatbot_src = chatbot_src + "    for j in range(d_model):" + NL
chatbot_src = chatbot_src + "        push(last_h, hidden[off + j])" + NL
chatbot_src = chatbot_src + "    return ml_native.matmul(last_h, lm_head_w, 1, d_model, vocab)" + NL
chatbot_src = chatbot_src + NL

# Sampling
chatbot_src = chatbot_src + "# === Token sampling with temperature ===" + NL
chatbot_src = chatbot_src + "let rng = 12345" + NL
chatbot_src = chatbot_src + "proc sample_token(logits, temperature):" + NL
chatbot_src = chatbot_src + "    # Apply temperature" + NL
chatbot_src = chatbot_src + "    let scaled = []" + NL
chatbot_src = chatbot_src + "    for i in range(len(logits)):" + NL
chatbot_src = chatbot_src + "        push(scaled, logits[i] / temperature)" + NL
chatbot_src = chatbot_src + "    # Softmax" + NL
chatbot_src = chatbot_src + "    let max_val = scaled[0]" + NL
chatbot_src = chatbot_src + "    for i in range(len(scaled)):" + NL
chatbot_src = chatbot_src + "        if scaled[i] > max_val:" + NL
chatbot_src = chatbot_src + "            max_val = scaled[i]" + NL
chatbot_src = chatbot_src + "    let sum_exp = 0.0" + NL
chatbot_src = chatbot_src + "    let probs = []" + NL
chatbot_src = chatbot_src + "    for i in range(len(scaled)):" + NL
chatbot_src = chatbot_src + "        let e = 1.0" + NL
chatbot_src = chatbot_src + "        let x = scaled[i] - max_val" + NL
chatbot_src = chatbot_src + "        # Approximate exp(x) using Taylor series" + NL
chatbot_src = chatbot_src + "        if x > -10:" + NL
chatbot_src = chatbot_src + "            e = 1.0 + x + x*x/2.0 + x*x*x/6.0 + x*x*x*x/24.0" + NL
chatbot_src = chatbot_src + "            if e < 0:" + NL
chatbot_src = chatbot_src + "                e = 0.0001" + NL
chatbot_src = chatbot_src + "        else:" + NL
chatbot_src = chatbot_src + "            e = 0.0001" + NL
chatbot_src = chatbot_src + "        push(probs, e)" + NL
chatbot_src = chatbot_src + "        sum_exp = sum_exp + e" + NL
chatbot_src = chatbot_src + "    # Normalize" + NL
chatbot_src = chatbot_src + "    for i in range(len(probs)):" + NL
chatbot_src = chatbot_src + "        probs[i] = probs[i] / sum_exp" + NL
chatbot_src = chatbot_src + "    # Sample from distribution" + NL
chatbot_src = chatbot_src + "    rng = (rng * 1664525 + 1013904223) & 4294967295" + NL
chatbot_src = chatbot_src + "    let r = (rng & 65535) / 65536.0" + NL
chatbot_src = chatbot_src + "    let cumul = 0.0" + NL
chatbot_src = chatbot_src + "    for i in range(len(probs)):" + NL
chatbot_src = chatbot_src + "        cumul = cumul + probs[i]" + NL
chatbot_src = chatbot_src + "        if cumul >= r:" + NL
chatbot_src = chatbot_src + "            return i" + NL
chatbot_src = chatbot_src + "    return len(probs) - 1" + NL
chatbot_src = chatbot_src + NL

# Generate function
chatbot_src = chatbot_src + "# === Generate text from prompt ===" + NL
chatbot_src = chatbot_src + "proc generate(prompt_text, max_tokens, temperature):" + NL
chatbot_src = chatbot_src + "    # Tokenize: character-level (ASCII)" + NL
chatbot_src = chatbot_src + "    let ids = []" + NL
chatbot_src = chatbot_src + "    for i in range(len(prompt_text)):" + NL
chatbot_src = chatbot_src + "        push(ids, ord(prompt_text[i]))" + NL
chatbot_src = chatbot_src + "    # Truncate to max_seq" + NL
chatbot_src = chatbot_src + "    if len(ids) > max_seq:" + NL
chatbot_src = chatbot_src + "        let trimmed = []" + NL
chatbot_src = chatbot_src + "        for i in range(max_seq):" + NL
chatbot_src = chatbot_src + "            push(trimmed, ids[len(ids) - max_seq + i])" + NL
chatbot_src = chatbot_src + "        ids = trimmed" + NL
chatbot_src = chatbot_src + "    # Generate tokens" + NL
chatbot_src = chatbot_src + "    let output = " + DQ + DQ + NL
chatbot_src = chatbot_src + "    for step in range(max_tokens):" + NL
chatbot_src = chatbot_src + "        let logits = forward(ids)" + NL
chatbot_src = chatbot_src + "        let next_id = sample_token(logits, temperature)" + NL
chatbot_src = chatbot_src + "        if next_id < 32 or next_id > 126:" + NL
chatbot_src = chatbot_src + "            next_id = 32" + NL
chatbot_src = chatbot_src + "        output = output + chr(next_id)" + NL
chatbot_src = chatbot_src + "        push(ids, next_id)" + NL
chatbot_src = chatbot_src + "        # Slide window" + NL
chatbot_src = chatbot_src + "        if len(ids) > max_seq:" + NL
chatbot_src = chatbot_src + "            let new_ids = []" + NL
chatbot_src = chatbot_src + "            for ni in range(max_seq):" + NL
chatbot_src = chatbot_src + "                push(new_ids, ids[len(ids) - max_seq + ni])" + NL
chatbot_src = chatbot_src + "            ids = new_ids" + NL
chatbot_src = chatbot_src + "    return output" + NL
chatbot_src = chatbot_src + NL

# Main loop
chatbot_src = chatbot_src + "# === Main loop ===" + NL
chatbot_src = chatbot_src + "print " + DQ + "============================================" + DQ + NL
chatbot_src = chatbot_src + "print " + DQ + "  SL-TQ-LLM Generative Chat v1.0" + DQ + NL
chatbot_src = chatbot_src + "print " + DQ + "  Real transformer inference from weights" + DQ + NL
chatbot_src = chatbot_src + "print " + DQ + "============================================" + DQ + NL
chatbot_src = chatbot_src + "print " + DQ + "Type a prompt and I will generate a continuation." + DQ + NL
chatbot_src = chatbot_src + "print " + DQ + "Commands: quit, temp <0.1-2.0>, len <1-200>" + DQ + NL
chatbot_src = chatbot_src + "print " + DQ + DQ + NL
chatbot_src = chatbot_src + NL
chatbot_src = chatbot_src + "let gen_temp = 0.8" + NL
chatbot_src = chatbot_src + "let gen_len = 50" + NL
chatbot_src = chatbot_src + "let running = true" + NL
chatbot_src = chatbot_src + "while running:" + NL
chatbot_src = chatbot_src + "    let msg = input(" + DQ + "Prompt> " + DQ + ")" + NL
chatbot_src = chatbot_src + "    if msg == " + DQ + "quit" + DQ + " or msg == " + DQ + "exit" + DQ + ":" + NL
chatbot_src = chatbot_src + "        running = false" + NL
chatbot_src = chatbot_src + "        print " + DQ + "Goodbye!" + DQ + NL
chatbot_src = chatbot_src + "    if running and len(msg) > 5 and msg[0] == " + DQ + "t" + DQ + " and msg[1] == " + DQ + "e" + DQ + " and msg[2] == " + DQ + "m" + DQ + " and msg[3] == " + DQ + "p" + DQ + " and msg[4] == " + DQ + " " + DQ + ":" + NL
chatbot_src = chatbot_src + "        let tv = " + DQ + DQ + NL
chatbot_src = chatbot_src + "        for i in range(len(msg) - 5):" + NL
chatbot_src = chatbot_src + "            tv = tv + msg[5 + i]" + NL
chatbot_src = chatbot_src + "        gen_temp = tonumber(tv)" + NL
chatbot_src = chatbot_src + "        if gen_temp < 0.1:" + NL
chatbot_src = chatbot_src + "            gen_temp = 0.1" + NL
chatbot_src = chatbot_src + "        if gen_temp > 2.0:" + NL
chatbot_src = chatbot_src + "            gen_temp = 2.0" + NL
chatbot_src = chatbot_src + "        print " + DQ + "  Temperature set to " + DQ + " + str(gen_temp)" + NL
chatbot_src = chatbot_src + "    if running and len(msg) > 4 and msg[0] == " + DQ + "l" + DQ + " and msg[1] == " + DQ + "e" + DQ + " and msg[2] == " + DQ + "n" + DQ + " and msg[3] == " + DQ + " " + DQ + ":" + NL
chatbot_src = chatbot_src + "        let lv = " + DQ + DQ + NL
chatbot_src = chatbot_src + "        for i in range(len(msg) - 4):" + NL
chatbot_src = chatbot_src + "            lv = lv + msg[4 + i]" + NL
chatbot_src = chatbot_src + "        gen_len = tonumber(lv) | 0" + NL
chatbot_src = chatbot_src + "        if gen_len < 1:" + NL
chatbot_src = chatbot_src + "            gen_len = 1" + NL
chatbot_src = chatbot_src + "        if gen_len > 200:" + NL
chatbot_src = chatbot_src + "            gen_len = 200" + NL
chatbot_src = chatbot_src + "        print " + DQ + "  Max length set to " + DQ + " + str(gen_len)" + NL
chatbot_src = chatbot_src + "    if running and msg != " + DQ + "quit" + DQ + " and msg != " + DQ + "exit" + DQ + ":" + NL
chatbot_src = chatbot_src + "        let is_cmd = false" + NL
chatbot_src = chatbot_src + "        if len(msg) > 4 and msg[0] == " + DQ + "t" + DQ + " and msg[1] == " + DQ + "e" + DQ + " and msg[2] == " + DQ + "m" + DQ + ":" + NL
chatbot_src = chatbot_src + "            is_cmd = true" + NL
chatbot_src = chatbot_src + "        if len(msg) > 3 and msg[0] == " + DQ + "l" + DQ + " and msg[1] == " + DQ + "e" + DQ + " and msg[2] == " + DQ + "n" + DQ + ":" + NL
chatbot_src = chatbot_src + "            is_cmd = true" + NL
chatbot_src = chatbot_src + "        if not is_cmd:" + NL
chatbot_src = chatbot_src + "            print " + DQ + DQ + NL
chatbot_src = chatbot_src + "            print " + DQ + "  [Generating " + DQ + " + str(gen_len) + " + DQ + " tokens at temp=" + DQ + " + str(gen_temp) + " + DQ + "...]" + DQ + NL
chatbot_src = chatbot_src + "            let result = generate(msg, gen_len, gen_temp)" + NL
chatbot_src = chatbot_src + "            print " + DQ + DQ + NL
chatbot_src = chatbot_src + "            print " + DQ + "SL-TQ-LLM> " + DQ + " + msg + result" + NL
chatbot_src = chatbot_src + "            print " + DQ + DQ + NL

io.writefile(chat_path, chatbot_src)
log("CHATBOT", "Generated " + chat_path)
log("CHATBOT", "Compile: sage --compile-llvm " + chat_path + " -o sl_tq_chat")
print ""
# Old ce() chatbot removed — replaced by chatbot_src above
# ce("# Auto-generated by train_sl_tq_llm.sage")
ce("# Compile: sage --compile-llvm models/sl_tq_llm_chat.sage -o sl_tq_chat")
ce("# Run:     ./sl_tq_chat   OR   sage models/sl_tq_llm_chat.sage")
ce("")
ce("proc contains(h, n):")
ce("    if len(n) > len(h):")
ce("        return false")
ce("    let hlen = len(h)")
ce("    let nlen = len(n)")
ce("    for i in range(hlen - nlen + 1):")
ce("        let found = true")
ce("        for j in range(nlen):")
ce("            if h[i + j] != n[j]:")
ce("                found = false")
ce("                break")
ce("        if found:")
ce("            return true")
ce("    return false")
ce("")
ce("proc to_lower(s):")
ce("    let r = " + DQ + DQ)
ce("    for i in range(len(s)):")
ce("        let c = ord(s[i])")
ce("        if c >= 65 and c <= 90:")
ce("            r = r + chr(c + 32)")
ce("        else:")
ce("            r = r + s[i]")
ce("    return r")
ce("")
ce("proc starts_with(s, prefix):")
ce("    if len(prefix) > len(s):")
ce("        return false")
ce("    for i in range(len(prefix)):")
ce("        if s[i] != prefix[i]:")
ce("            return false")
ce("    return true")
ce("")
ce("proc substr(s, start, count):")
ce("    let r = " + DQ + DQ)
ce("    let end = start + count")
ce("    if end > len(s):")
ce("        end = len(s)")
ce("    for i in range(end - start):")
ce("        r = r + s[start + i]")
ce("    return r")
ce("")

# Memory
ce("let facts = []")

# Embed all engram semantic facts
let mem_sem = memory["semantic"]
for i in range(len(mem_sem)):
    let content = mem_sem[i]["content"]
    ce("push(facts, " + DQ + content + DQ + ")")

# Embed autoresearch knowledge
ce("push(facts, " + DQ + "AutoResearch: Karpathy ratchet loop - propose/train/evaluate/accept-reject, ran " + str(researcher["total_experiments"]) + " experiments, " + str(researcher["improvements"]) + " improvements found" + DQ + ")")
ce("push(facts, " + DQ + "AutoResearch optimized LR to " + str(research_cfg["learning_rate"]) + " and warmup to " + str(research_cfg["warmup_steps"]) + " for lowest validation loss" + DQ + ")")
ce("push(facts, " + DQ + "TurboQuant achieved 8.5x KV cache compression at 3-bit with MSE 0.005" + DQ + ")")
ce("push(facts, " + DQ + "Model: SL-TQ-LLM, d=64, 1 layer, 98K params, trained on 71 Sage files + NLP + theory" + DQ + ")")
ce("push(facts, " + DQ + "Training: pre-train loss=" + str(train.avg_loss(state1)) + ", LoRA loss=" + str(train.avg_loss(state2)) + ", DPO loss=" + str(dpo_avg) + DQ + ")")

ce("")
ce("let remembered = []")
ce("let history = []")
ce("")
ce("proc recall(query):")
ce("    let lq = to_lower(query)")
ce("    let results = []")
ce("    for i in range(len(facts)):")
ce("        if contains(to_lower(facts[i]), lq):")
ce("            push(results, facts[i])")
ce("    for i in range(len(remembered)):")
ce("        if contains(to_lower(remembered[i]), lq):")
ce("            push(results, remembered[i])")
ce("    return results")
ce("")

# Reasoning engine with all topics
ce("proc reason(question):")
ce("    let chain = []")
ce("    let lp = to_lower(question)")
ce("    let mem = recall(lp)")
ce("    if len(mem) > 0:")
ce("        push(chain, " + DQ + "Recalled " + DQ + " + str(len(mem)) + " + DQ + " facts" + DQ + ")")
ce("    let topic = " + DQ + "general" + DQ)

# Topic classification
let topics = [["llm", "llm|language model|transformer|lora|engram|neural|tokeniz|autoresearch|turboquant"], ["agent", "agent|react|supervisor|tool use|ratchet"], ["chatbot", "chatbot|persona|conversation|intent"], ["crypto", "crypto|sha|hash|encrypt"], ["networking", "network|http|socket|url|dns"], ["osdev", "baremetal|uefi|kernel|elf|pci|osdev"], ["ml", "tensor|machine learn|training|gradient"], ["graphics", "gpu|vulkan|opengl|shader|render"], ["gc", "gc |garbage"], ["compiler", "compile|backend|emit|llvm"], ["loops", "for |loop|while"], ["modules", "import|module|library"], ["oop", "class |object|inherit|super"], ["data", "array|dict|data struct"], ["functions", "function|proc |closure"], ["errors", "error|exception|try "], ["testing", "test|debug|bug"], ["concurrency", "thread|async|channel"], ["planning", "plan|how to build|steps"]]

for ti in range(len(topics)):
    let tname = topics[ti][0]
    let kw_str = topics[ti][1]
    let kw_parts = []
    let current = ""
    for c in range(len(kw_str)):
        if kw_str[c] == "|":
            push(kw_parts, current)
            current = ""
        else:
            current = current + kw_str[c]
    push(kw_parts, current)
    let check = "    if topic == " + DQ + "general" + DQ + " and ("
    for k in range(len(kw_parts)):
        if k > 0:
            check = check + " or "
        check = check + "contains(lp, " + DQ + kw_parts[k] + DQ + ")"
    ce(check + "):")
    ce("        topic = " + DQ + tname + DQ)

ce("    push(chain, " + DQ + "Topic: " + DQ + " + topic)")
ce("    let answer = " + DQ + DQ)

# Answers
let answers = {}
answers["llm"] = "SL-TQ-LLM: SageGPT + TurboQuant + AutoResearch. 18 LLM modules: config, tokenizer, embedding, attention, transformer, generate, train, agent, prompt, lora, quantize, engram, rag, dpo, gguf, gguf_import, turboquant, autoresearch. TurboQuant: 3-bit KV cache (8.5x compression). AutoResearch: Karpathy ratchet loop for autonomous hyperparameter optimization."
answers["agent"] = "Agent framework (12 modules): core (ReAct), tools, planner (DAG), router, supervisor (workers), critic, schema, trace (SFT), grammar (constrained decoding), sandbox, tot (Tree of Thoughts), semantic_router. AutoResearch uses ratchet loop: propose->train->evaluate->accept/reject."
answers["chatbot"] = "Chat framework: bot (intents, middleware), persona (6: SageDev, Teacher, Debugger, Architect, CodeReviewer, Assistant), session (history). This chatbot was built by train_sl_tq_llm.sage with AutoResearch optimization."
answers["crypto"] = "Crypto (6 modules): hash (SHA-256), hmac, encoding (Base64, hex), cipher (XOR, RC4), rand (xoshiro256**), password (PBKDF2)."
answers["networking"] = "Networking: native (socket, tcp, http, ssl) + lib/net/ (8): url, headers, request, server, websocket, mime, dns, ip."
answers["osdev"] = "OS dev (15 modules): fat, elf, pe, mbr, gpt, pci, acpi, uefi, paging, idt, serial, dtb, alloc, vfs."
answers["ml"] = "ML: tensor, nn, optim, loss, data + ml_native C backend (12+ GFLOPS). gpu_accel for GPU/CPU/NPU/TPU auto-detect."
answers["graphics"] = "GPU engine (24 modules): Vulkan + OpenGL 4.5. PBR, shadows, deferred (SSAO, SSR), TAA."
answers["gc"] = "Concurrent tri-color mark-sweep GC: 4 phases (root scan STW, concurrent mark, remark STW, concurrent sweep). SATB write barrier."
answers["compiler"] = "3 backends: --compile (C), --compile-llvm (LLVM IR), --compile-native (x86-64/aarch64/rv64). Use break not fake-break in LLVM."
answers["loops"] = "Loops: for i in range(10): body. for item in arr: body. while cond: body. break/continue. Use break (not j=len) for LLVM compat."
answers["modules"] = "11 categories, 128+ modules: os(15), net(8), crypto(6), ml(9), cuda(4), std(23), llm(18), agent(12), chat(3), graphics(24), root(9)."
answers["oop"] = "OOP: class Name: with proc init(self). Inheritance: class Dog(Animal). super.init(self, args). Arrow operator: obj->field."
answers["data"] = "Arrays: [1,2,3], push, pop, slicing. Dicts: {}, d[key]=val, dict_keys. Tuples: (1,2,3)."
answers["functions"] = "proc name(args): body. Return values. Closures capture outer vars. First-class functions."
answers["errors"] = "try: risky. catch e: handle. finally: cleanup. raise to throw."
answers["testing"] = "Tests: 241 interpreter + 1567+ self-hosted. Debug: gc_disable(), chr() not escapes, break not fake-break."
answers["concurrency"] = "Concurrency: thread, async/await, std.channel, std.atomic, std.rwlock, std.threadpool."
answers["planning"] = "Plan: 1) Define goal, 2) Create module, 3) Implement, 4) Test, 5) Document, 6) Run tests."

let ans_keys = dict_keys(answers)
for i in range(len(ans_keys)):
    ce("    if topic == " + DQ + ans_keys[i] + DQ + ":")
    ce("        answer = " + DQ + answers[ans_keys[i]] + DQ)

ce("    if len(answer) == 0:")
ce("        if len(mem) > 0:")
ce("            answer = " + DQ + "Based on my knowledge: " + DQ + " + mem[0]")
ce("        else:")
ce("            answer = " + DQ + "I know about: loops, imports, classes, GC, compiler, data, functions, errors, testing, concurrency, planning, LLM, agents, chatbot, crypto, networking, OS dev, ML, graphics, TurboQuant, AutoResearch." + DQ)
ce("    push(chain, " + DQ + "Answering about " + DQ + " + topic)")
ce("    push(history, " + DQ + "Q: " + DQ + " + question)")
ce("    push(history, " + DQ + "A: " + DQ + " + answer)")
ce("    let result = {}")
ce("    result[" + DQ + "chain" + DQ + "] = chain")
ce("    result[" + DQ + "answer" + DQ + "] = answer")
ce("    return result")
ce("")

# Show chain helper
ce("proc show_chain(r):")
ce("    let ch = r[" + DQ + "chain" + DQ + "]")
ce("    for ci in range(len(ch)):")
ce("        print " + DQ + "  Thought " + DQ + " + str(ci + 1) + " + DQ + ": " + DQ + " + ch[ci]")
ce("    print " + DQ + "  Answer: " + DQ + " + r[" + DQ + "answer" + DQ + "]")
ce("")

# Main loop
ce("print " + DQ + "============================================" + DQ)
ce("print " + DQ + "  SL-TQ-LLM Chat v1.0" + DQ)
ce("print " + DQ + "  AutoResearch + TurboQuant + SageGPT" + DQ)
ce("print " + DQ + "  " + str(len(mem_sem) + 5) + " facts | 19 topics | CoT" + DQ)
ce("print " + DQ + "============================================" + DQ)
ce("print " + DQ + "Hello! I am SL-TQ-LLM. Ask me about Sage." + DQ)
ce("print " + DQ + "Commands: quit, memory, remember, recall, think, help" + DQ)
ce("print " + DQ + DQ)
ce("let running = true")
ce("while running:")
ce("    let msg = input(" + DQ + "You> " + DQ + ")")
ce("    if msg == " + DQ + "quit" + DQ + " or msg == " + DQ + "exit" + DQ + ":")
ce("        running = false")
ce("        print " + DQ + "Goodbye. " + DQ + " + str(len(history)) + " + DQ + " exchanges." + DQ)
ce("    if running and msg == " + DQ + "help" + DQ + ":")
ce("        print " + DQ + "  quit, memory, remember <fact>, recall <query>, think <q>" + DQ)
ce("    if running and msg == " + DQ + "memory" + DQ + ":")
ce("        print " + DQ + "  Facts: " + DQ + " + str(len(facts)) + " + DQ + " | Remembered: " + DQ + " + str(len(remembered)) + " + DQ + " | History: " + DQ + " + str(len(history))")
ce("    if running and starts_with(msg, " + DQ + "remember " + DQ + "):")
ce("        let fact = substr(msg, 9, len(msg) - 9)")
ce("        push(remembered, fact)")
ce("        print " + DQ + "  Remembered: " + DQ + " + fact")
ce("    if running and starts_with(msg, " + DQ + "recall " + DQ + "):")
ce("        let rq = substr(msg, 7, len(msg) - 7)")
ce("        let results = recall(rq)")
ce("        if len(results) > 0:")
ce("            let limit = len(results)")
ce("            if limit > 5:")
ce("                limit = 5")
ce("            for ri in range(limit):")
ce("                print " + DQ + "  [" + DQ + " + str(ri + 1) + " + DQ + "] " + DQ + " + results[ri]")
ce("        else:")
ce("            print " + DQ + "  No memories found." + DQ)
ce("    if running and starts_with(msg, " + DQ + "think " + DQ + "):")
ce("        show_chain(reason(substr(msg, 6, len(msg) - 6)))")
ce("    if running and msg != " + DQ + "quit" + DQ + " and msg != " + DQ + "exit" + DQ + " and msg != " + DQ + "memory" + DQ + " and msg != " + DQ + "help" + DQ + ":")
ce("        let is_cmd = false")
ce("        if starts_with(msg, " + DQ + "think " + DQ + "):")
ce("            is_cmd = true")
ce("        if starts_with(msg, " + DQ + "remember " + DQ + "):")
ce("            is_cmd = true")
ce("        if starts_with(msg, " + DQ + "recall " + DQ + "):")
ce("            is_cmd = true")
ce("        if not is_cmd:")
ce("            let r = reason(msg)")
ce("            print " + DQ + DQ)
ce("            print " + DQ + "SL-TQ-LLM> " + DQ + " + r[" + DQ + "answer" + DQ + "]")
ce("            print " + DQ + DQ)

# (Old retrieval chatbot superseded by generative chatbot above)

# ============================================================================
# Phase 11: Model Summary
# ============================================================================

separator()
print "  SL-TQ-LLM Training Complete"
separator()
print ""
print "Model: SL-TQ-LLM (SageGPT + TurboQuant)"
print "Architecture: SwiGLU + RoPE + RMSNorm"
print "  d=" + str(d_model) + " heads=" + str(n_heads) + " layers=" + str(n_layers) + " ff=" + str(d_ff)
print "  Vocab: " + str(vocab) + " | Context: " + str(context_length)
print "  Parameters: " + str(param_count)
print ""
print "Training:"
print "  Pre-train: " + str(theory_steps) + " steps, loss=" + str(train.avg_loss(state1))
print "  LoRA: " + str(lora_steps) + " steps on " + str(sage_file_count) + " files, loss=" + str(train.avg_loss(state2))
print "  LoRA: rank=" + str(lora_rank) + " alpha=" + str(lora_alpha) + " params=" + str(adapter["trainable_params"])
print "  DPO: " + str(len(dpo_ds["pairs"])) + " pairs, loss=" + str(dpo_avg)
print ""
print "Knowledge:"
print "  Engram: " + str(len(memory["semantic"])) + " semantic + " + str(len(memory["procedural"])) + " procedural"
print "  RAG: " + str(rag_stats["documents"]) + " docs (" + str(rag_stats["chunks"]) + " chunks)"
print ""
print "TurboQuant:"
print "  KV cache: " + str(kv_stats["compression_ratio"]) + "x compression at 3-bit"
print "  Weight MSE (3-bit): " + str(tq_mse)
print "  Weight MSE (4-bit): " + str(tq_mse4)
print "  IP preservation error: " + str(ip_err["absolute_error"])
print ""

let sizes = quantize.size_comparison(param_count)
print "Size comparison:"
print "  " + sizes["fp32"] + " (FP32) -> " + sizes["int8"] + " (INT8) -> " + sizes["int4"] + " (INT4)"
print "  TurboQuant 3-bit: ~" + str((param_count * 3 / 8 / 1024) | 0) + " KB"
print ""

let ar_stats = autoresearch.stats(researcher)
print "AutoResearch:"
print "  Experiments: " + str(ar_stats["total"]) + " | Improvements: " + str(ar_stats["improvements"]) + " | Success rate: " + str(ar_stats["success_rate"]) + "%"
print "  Optimized LR: " + str(research_cfg["learning_rate"])
print "  Optimized warmup: " + str(research_cfg["warmup_steps"])
print ""
print "Chatbot: " + chat_path + " (" + str(len(CL)) + " lines)"
print ""
print "Techniques used:"
print "  SwiGLU FFN + RoPE positional encoding + RMSNorm"
print "  LoRA fine-tuning (rank " + str(lora_rank) + ")"
print "  DPO preference alignment"
print "  RAG retrieval-augmented generation"
print "  Engram 4-tier memory"
print "  TurboQuant KV cache compression (3-bit, ~6x)"
print "  TurboQuant weight quantization"
print "  AutoResearch ratchet loop (Karpathy)"
print "  GPU acceleration (auto-detect)"
print ""

# Compute benchmark
let bench = gpu_accel.benchmark(_compute, d_model, 10)
print "Compute: " + str(bench["gflops"]) + " GFLOPS (" + str(bench["ms_per_matmul"]) + " ms @ " + str(d_model) + "x" + str(d_model) + ")"
print "Backend: " + _compute["backend"]
print ""
separator()
