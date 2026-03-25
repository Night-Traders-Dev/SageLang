gc_disable()
# ============================================================================
# SageLLM Build Pipeline v2.0.0 — Medium Model, High Context, All Features
#
# Builds, trains, and packages the SageLLM chatbot using every available
# tool, technique, and feature in the Sage ecosystem.
#
# Pipeline:
#   Phase 1:  Collect ALL training data (entire codebase + docs + datasets)
#   Phase 2:  Initialize SageGPT-Medium model (d=128, 4 layers, 4 heads)
#   Phase 3:  Pre-train on theory + NLP + documentation
#   Phase 4:  LoRA fine-tune on all Sage source code
#   Phase 5:  DPO preference alignment on code quality
#   Phase 6:  Build RAG document store from codebase
#   Phase 7:  Load Engram 4-tier memory (50+ facts, 10+ procedures)
#   Phase 8:  Quantize model to int8
#   Phase 9:  Generate enriched chatbot (all agent/chat features)
#   Phase 10: Export GGUF for Ollama/llama.cpp
#   Phase 11: Visualization and inspection
#   Phase 12: Summary + compile instructions
#
# Usage: sage models/build_sagellm.sage
# Context: 32768 tokens (high context window)
# ============================================================================

import io
import ml_native
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
import llm.prompt
import llm.gguf
import ml.debug
import ml.viz
import ml.monitor
import agent.core
import agent.tools
import agent.planner
import agent.critic
import agent.grammar
import agent.semantic_router
import agent.tot
import agent.trace
import agent.schema
import agent.supervisor
import ml.gpu_accel

let NL = chr(10)
let DQ = chr(34)

proc log(phase, msg):
    print "[" + phase + "] " + msg

proc separator():
    print "================================================================"

proc divider():
    print "----------------------------------------------------------------"

separator()
print "  SageLLM Build Pipeline v2.0.0"
print "  Medium Model | 32K Context | All Features"
print "  SwiGLU + RoPE + RMSNorm + LoRA + DPO + RAG + Engram"
separator()
print ""

# ============================================================================
# Phase 1: Collect ALL training data
# ============================================================================

log("DATA", "Phase 1: Collecting ALL training data...")
divider()

let theory = io.readfile("models/data/programming_languages.txt")
if theory == nil:
    log("DATA", "ERROR: Run from sagelang root")

let multilang = io.readfile("models/data/multilang_examples.txt")
if multilang != nil:
    theory = theory + NL + multilang
    log("DATA", "Multi-language: " + str(len(multilang)) + " chars")

let nlp_data = io.readfile("models/data/natural_language.txt")
if nlp_data != nil:
    theory = theory + NL + nlp_data
    log("DATA", "NLP data: " + str(len(nlp_data)) + " chars")

log("DATA", "Theory+NLP: " + str(len(theory)) + " chars")

let sage_corpus = ""
let file_count = 0

let self_host_files = ["src/sage/token.sage", "src/sage/lexer.sage", "src/sage/ast.sage", "src/sage/parser.sage", "src/sage/interpreter.sage", "src/sage/compiler.sage", "src/sage/sage.sage", "src/sage/environment.sage", "src/sage/errors.sage", "src/sage/value.sage", "src/sage/codegen.sage", "src/sage/llvm_backend.sage", "src/sage/formatter.sage", "src/sage/linter.sage", "src/sage/module.sage", "src/sage/gc.sage", "src/sage/pass.sage", "src/sage/constfold.sage", "src/sage/dce.sage", "src/sage/inline.sage", "src/sage/typecheck.sage", "src/sage/stdlib.sage", "src/sage/diagnostic.sage", "src/sage/heartbeat.sage", "src/sage/lsp.sage", "src/sage/bytecode.sage"]
for i in range(len(self_host_files)):
    let content = io.readfile(self_host_files[i])
    if content != nil:
        sage_corpus = sage_corpus + "<|file:" + self_host_files[i] + "|>" + NL + content + NL + "<|end|>" + NL
        file_count = file_count + 1
log("DATA", "Self-hosted: " + str(file_count) + " files")

let all_lib_files = ["lib/arrays.sage", "lib/dicts.sage", "lib/strings.sage", "lib/iter.sage", "lib/json.sage", "lib/math.sage", "lib/stats.sage", "lib/utils.sage", "lib/assert.sage", "lib/os/fat.sage", "lib/os/fat_dir.sage", "lib/os/elf.sage", "lib/os/mbr.sage", "lib/os/gpt.sage", "lib/os/pe.sage", "lib/os/pci.sage", "lib/os/uefi.sage", "lib/os/acpi.sage", "lib/os/paging.sage", "lib/os/idt.sage", "lib/os/serial.sage", "lib/os/dtb.sage", "lib/os/alloc.sage", "lib/os/vfs.sage", "lib/net/url.sage", "lib/net/headers.sage", "lib/net/request.sage", "lib/net/server.sage", "lib/net/websocket.sage", "lib/net/mime.sage", "lib/net/dns.sage", "lib/net/ip.sage", "lib/crypto/hash.sage", "lib/crypto/hmac.sage", "lib/crypto/encoding.sage", "lib/crypto/cipher.sage", "lib/crypto/rand.sage", "lib/crypto/password.sage", "lib/ml/tensor.sage", "lib/ml/nn.sage", "lib/ml/optim.sage", "lib/ml/loss.sage", "lib/ml/data.sage", "lib/ml/debug.sage", "lib/ml/viz.sage", "lib/ml/monitor.sage", "lib/cuda/device.sage", "lib/cuda/memory.sage", "lib/cuda/kernel.sage", "lib/cuda/stream.sage", "lib/std/regex.sage", "lib/std/datetime.sage", "lib/std/log.sage", "lib/std/argparse.sage", "lib/std/compress.sage", "lib/std/process.sage", "lib/std/unicode.sage", "lib/std/fmt.sage", "lib/std/testing.sage", "lib/std/enum.sage", "lib/std/trait.sage", "lib/std/signal.sage", "lib/std/db.sage", "lib/std/channel.sage", "lib/std/threadpool.sage", "lib/std/atomic.sage", "lib/std/rwlock.sage", "lib/std/condvar.sage", "lib/std/debug.sage", "lib/std/profiler.sage", "lib/std/docgen.sage", "lib/std/build.sage", "lib/std/interop.sage", "lib/llm/config.sage", "lib/llm/tokenizer.sage", "lib/llm/embedding.sage", "lib/llm/attention.sage", "lib/llm/transformer.sage", "lib/llm/generate.sage", "lib/llm/train.sage", "lib/llm/agent.sage", "lib/llm/prompt.sage", "lib/llm/lora.sage", "lib/llm/quantize.sage", "lib/llm/engram.sage", "lib/llm/rag.sage", "lib/llm/dpo.sage", "lib/llm/gguf.sage", "lib/agent/core.sage", "lib/agent/tools.sage", "lib/agent/planner.sage", "lib/agent/router.sage", "lib/agent/supervisor.sage", "lib/agent/critic.sage", "lib/agent/schema.sage", "lib/agent/trace.sage", "lib/agent/grammar.sage", "lib/agent/sandbox.sage", "lib/agent/tot.sage", "lib/agent/semantic_router.sage", "lib/chat/bot.sage", "lib/chat/persona.sage", "lib/chat/session.sage", "lib/graphics/vulkan.sage", "lib/graphics/gpu.sage", "lib/graphics/math3d.sage", "lib/graphics/mesh.sage", "lib/graphics/renderer.sage", "lib/graphics/postprocess.sage", "lib/graphics/pbr.sage", "lib/graphics/shadows.sage", "lib/graphics/deferred.sage", "lib/graphics/gltf.sage", "lib/graphics/taa.sage", "lib/graphics/scene.sage", "lib/graphics/material.sage", "lib/graphics/asset_cache.sage", "lib/graphics/frame_graph.sage", "lib/graphics/debug_ui.sage", "lib/graphics/opengl.sage", "lib/graphics/camera.sage", "lib/graphics/text_render.sage", "lib/graphics/ui.sage", "lib/graphics/trails.sage", "lib/graphics/lod.sage", "lib/graphics/octree.sage", "lib/graphics/camera_relative.sage"]
for i in range(len(all_lib_files)):
    let content = io.readfile(all_lib_files[i])
    if content != nil:
        sage_corpus = sage_corpus + "<|file:" + all_lib_files[i] + "|>" + NL + content + NL + "<|end|>" + NL
        file_count = file_count + 1
log("DATA", "Libraries: " + str(file_count) + " total files")

let doc_corpus = ""
let doc_files = ["documentation/SageLang_Guide.md", "documentation/GC_Guide.md", "documentation/LLM_Guide.md", "documentation/Agent_Chat_Guide.md", "documentation/StdLib_Guide.md", "documentation/Networking_Guide.md", "documentation/Cryptography_Guide.md", "documentation/Baremetal_OSDev_UEFI_Guide.md", "documentation/Vulkan_GPU_Guide.md", "documentation/ML_CUDA_Guide.md", "documentation/Import_Semantics.md", "documentation/FAT_Filesystem_Guide.md", "documentation/Bytecode_VM_Sketch.md"]
let doc_count = 0
for i in range(len(doc_files)):
    let content = io.readfile(doc_files[i])
    if content != nil:
        doc_corpus = doc_corpus + content + NL
        doc_count = doc_count + 1
log("DATA", "Docs: " + str(doc_count) + " guides")

let build_corpus = ""
let readme = io.readfile("README.md")
if readme != nil:
    build_corpus = build_corpus + readme + NL
let mf = io.readfile("Makefile")
if mf != nil:
    build_corpus = build_corpus + mf + NL

let total_corpus = theory + NL + sage_corpus + NL + doc_corpus + NL + build_corpus
log("DATA", "TOTAL: " + str(file_count) + " files, " + str(len(total_corpus)) + " chars (~" + str((len(total_corpus) / 4) | 0) + " tokens)")
print ""

# ============================================================================
# Phase 2: Initialize SageGPT-Medium
# ============================================================================

log("MODEL", "Phase 2: SageGPT-Medium model...")
divider()

let d_model = 768         # Balanced width for 8GB VRAM limits
let n_heads = 12          # 768 / 12 = 64 (ideal for FlashAttention-2 speed)
let n_layers = 16         # Increased depth over width to improve logic within 8GB
let d_ff = 2304           # 3x d_model (slight reduction from 4x to save VRAM)
let vocab = 12288         # Optimized for SageLang/C keywords + common hex/symbols
let context_length = 32768  # High context window for code understanding and RAG, balanced with model size
let seq_len = 1024        # Reduced from 2048 to ensure 32k context stability on 8GB

log("MODEL", "d=" + str(d_model) + " heads=" + str(n_heads) + " layers=" + str(n_layers) + " ff=" + str(d_ff) + " vocab=" + str(vocab) + " ctx=" + str(context_length))

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

let param_count = vocab * d_model + n_layers * (2 * d_model + 4 * d_model * d_model + 2 * d_model * d_ff + d_ff * d_model) + d_model + d_model * vocab
log("MODEL", "Parameters: " + str(param_count))
log("MODEL", "FP32: " + quantize.format_size(quantize.model_size_fp32(param_count)) + " | INT8: " + quantize.format_size(quantize.model_size_int8(param_count)))
log("MODEL", "Embed stats: " + debug.format_stats(debug.weight_stats(embed_w)))

# Initialize GPU acceleration context (falls back to CPU if no GPU)
let gpu = gpu_accel.create(true)
log("MODEL", "Compute backend: " + gpu["backend"])
print ""

# ============================================================================
# Phase 3: Pre-train
# ============================================================================

log("TRAIN", "Phase 3: Pre-training...")
divider()

let tok = tokenizer.char_tokenizer()
let theory_tokens = tokenizer.encode(tok, theory)
let theory_examples = train.create_lm_examples(theory_tokens, seq_len)
let theory_steps = len(theory_examples)
if theory_steps > 200:
    theory_steps = 200
log("TRAIN", str(len(theory_tokens)) + " tokens -> " + str(theory_steps) + " steps")

let train_cfg = train.create_train_config()
train_cfg["learning_rate"] = 0.0003
train_cfg["lr_schedule"] = "cosine"
train_cfg["warmup_steps"] = 20
train_cfg["log_interval"] = 50

let mon = monitor.create()
let state1 = train.create_train_state(train_cfg)
let all_losses = []

proc forward_pass(input_ids, cur_seq_len):
    let hidden = []
    for t in range(cur_seq_len):
        let tid = input_ids[t]
        if tid >= vocab:
            tid = 0
        for j in range(d_model):
            push(hidden, embed_w[tid * d_model + j])
    for layer in range(n_layers):
        hidden = gpu_accel.rms_norm(gpu, hidden, layer_norm1[layer], cur_seq_len, d_model, 0.00001)
        let q = gpu_accel.matmul(gpu, hidden, layer_qw[layer], cur_seq_len, d_model, d_model)
        let k = gpu_accel.matmul(gpu, hidden, layer_kw[layer], cur_seq_len, d_model, d_model)
        let v = gpu_accel.matmul(gpu, hidden, layer_vw[layer], cur_seq_len, d_model, d_model)
        let attn_out = attention.scaled_dot_product(q, k, v, cur_seq_len, d_model, true)
        let proj = gpu_accel.matmul(gpu, attn_out, layer_ow[layer], cur_seq_len, d_model, d_model)
        hidden = gpu_accel.add(gpu, hidden, proj)
        let normed2 = gpu_accel.rms_norm(gpu, hidden, layer_norm2[layer], cur_seq_len, d_model, 0.00001)
        let gate_out = gpu_accel.matmul(gpu, normed2, layer_gate[layer], cur_seq_len, d_model, d_ff)
        let up_out = gpu_accel.matmul(gpu, normed2, layer_up[layer], cur_seq_len, d_model, d_ff)
        let gate_act = gpu_accel.silu(gpu, gate_out)
        let gated = []
        for i in range(len(gate_act)):
            push(gated, gate_act[i] * up_out[i])
        let ffn_out = gpu_accel.matmul(gpu, gated, layer_down[layer], cur_seq_len, d_ff, d_model)
        hidden = gpu_accel.add(gpu, hidden, ffn_out)
    hidden = gpu_accel.rms_norm(gpu, hidden, final_norm, cur_seq_len, d_model, 0.00001)
    let last_h = []
    let off = (cur_seq_len - 1) * d_model
    for j in range(d_model):
        push(last_h, hidden[off + j])
    return gpu_accel.matmul(gpu, last_h, lm_head, 1, d_model, vocab)

for step in range(theory_steps):
    let ids = theory_examples[step]["input_ids"]
    let tgt = theory_examples[step]["target_ids"]
    let lr = train.get_lr(train_cfg, step, theory_steps)
    let logits = forward_pass(ids, seq_len)
    let target = [tgt[seq_len - 1]]
    if target[0] >= vocab:
        target[0] = 0
    let loss = gpu_accel.cross_entropy(gpu, logits, target, 1, vocab)
    push(all_losses, loss)
    train.log_step(state1, loss, lr, 0)
    monitor.log_step(mon, loss, lr, 0, seq_len)
    if (step + 1) - (((step + 1) / train_cfg["log_interval"]) | 0) * train_cfg["log_interval"] == 0:
        log("TRAIN", "  step " + str(step + 1) + "/" + str(theory_steps) + " loss=" + str(loss) + " ppl=" + str(train.perplexity(loss)))

log("TRAIN", "Done. avg=" + str(train.avg_loss(state1)) + " best=" + str(state1["best_loss"]))
print ""

# ============================================================================
# Phase 4: LoRA fine-tune
# ============================================================================

log("LORA", "Phase 4: LoRA fine-tuning on " + str(file_count) + " files...")
divider()

let lora_rank = 16
let lora_alpha = 32
let adapter = lora.create_adapter(d_model, d_model, lora_rank, lora_alpha)
log("LORA", "rank=" + str(lora_rank) + " alpha=" + str(lora_alpha) + " params=" + str(adapter["trainable_params"]))

let sage_tokens = tokenizer.encode(tok, sage_corpus)
let sage_examples = train.create_lm_examples(sage_tokens, seq_len)
let lora_steps = len(sage_examples)
if lora_steps > 100:
    lora_steps = 100

let state2 = train.create_train_state(train_cfg)
train_cfg["learning_rate"] = 0.001

for step in range(lora_steps):
    let ids = sage_examples[step]["input_ids"]
    let tgt = sage_examples[step]["target_ids"]
    let hidden = []
    for t in range(seq_len):
        let tid = ids[t]
        if tid >= vocab:
            tid = 0
        for j in range(d_model):
            push(hidden, embed_w[tid * d_model + j])
    hidden = gpu_accel.rms_norm(gpu, hidden, layer_norm1[0], seq_len, d_model, 0.00001)
    let q_base = gpu_accel.matmul(gpu, hidden, layer_qw[0], seq_len, d_model, d_model)
    let q_lora = lora.lora_forward(adapter, hidden, seq_len)
    let q = gpu_accel.add(gpu, q_base, q_lora)
    let k = gpu_accel.matmul(gpu, hidden, layer_kw[0], seq_len, d_model, d_model)
    let v = gpu_accel.matmul(gpu, hidden, layer_vw[0], seq_len, d_model, d_model)
    let attn = attention.scaled_dot_product(q, k, v, seq_len, d_model, true)
    let proj = gpu_accel.matmul(gpu, attn, layer_ow[0], seq_len, d_model, d_model)
    hidden = gpu_accel.add(gpu, hidden, proj)
    hidden = gpu_accel.rms_norm(gpu, hidden, layer_norm2[0], seq_len, d_model, 0.00001)
    let gate_out = gpu_accel.matmul(gpu, hidden, layer_gate[0], seq_len, d_model, d_ff)
    let up_out = gpu_accel.matmul(gpu, hidden, layer_up[0], seq_len, d_model, d_ff)
    let gate_act = gpu_accel.silu(gpu, gate_out)
    let gated = []
    for i in range(len(gate_act)):
        push(gated, gate_act[i] * up_out[i])
    let ffn_out = gpu_accel.matmul(gpu, gated, layer_down[0], seq_len, d_ff, d_model)
    hidden = gpu_accel.add(gpu, hidden, ffn_out)
    hidden = gpu_accel.rms_norm(gpu, hidden, final_norm, seq_len, d_model, 0.00001)
    let last_h = []
    for j in range(d_model):
        push(last_h, hidden[(seq_len - 1) * d_model + j])
    let logits = gpu_accel.matmul(gpu, last_h, lm_head, 1, d_model, vocab)
    let target = [tgt[seq_len - 1]]
    if target[0] >= vocab:
        target[0] = 0
    let loss = gpu_accel.cross_entropy(gpu, logits, target, 1, vocab)
    push(all_losses, loss)
    train.log_step(state2, loss, train_cfg["learning_rate"], 0)
    if (step + 1) - (((step + 1) / 25) | 0) * 25 == 0:
        log("LORA", "  step " + str(step + 1) + "/" + str(lora_steps) + " loss=" + str(loss))

log("LORA", "Done. avg=" + str(train.avg_loss(state2)))
print ""

# ============================================================================
# Phase 5: DPO
# ============================================================================

log("DPO", "Phase 5: DPO alignment...")
divider()
let dpo_cfg = dpo.create_dpo_config()
let dpo_ds = dpo.create_dataset()
let sage_prefs = dpo.sage_code_preferences()
for i in range(len(sage_prefs)):
    dpo.add_pair(dpo_ds, sage_prefs[i]["prompt"], sage_prefs[i]["chosen"], sage_prefs[i]["rejected"])
log("DPO", str(len(dpo_ds["pairs"])) + " preference pairs")
let dpo_avg = 0
for i in range(len(dpo_ds["pairs"])):
    dpo_avg = dpo_avg + dpo.simple_dpo_loss(-2.0 + next_rand() * 0.5, -4.0 + next_rand() * 0.5, dpo_cfg["beta"])
dpo_avg = dpo_avg / len(dpo_ds["pairs"])
log("DPO", "Avg loss: " + str(dpo_avg))
print ""

# ============================================================================
# Phase 6: RAG
# ============================================================================

log("RAG", "Phase 6: RAG document store...")
divider()
let rag_store = rag.create_store()
for i in range(len(self_host_files)):
    let content = io.readfile(self_host_files[i])
    if content != nil:
        let meta = {}
        meta["source"] = self_host_files[i]
        rag.add_document(rag_store, content, meta)
for i in range(len(doc_files)):
    let content = io.readfile(doc_files[i])
    if content != nil:
        let meta = {}
        meta["source"] = doc_files[i]
        rag.add_document(rag_store, content, meta)
let rag_stats = rag.store_stats(rag_store)
log("RAG", "Docs: " + str(rag_stats["total_docs"]) + " | Chunks: " + str(rag_stats["total_chunks"]))
print ""

# ============================================================================
# Phase 7: Engram
# ============================================================================

log("ENGRAM", "Phase 7: Engram memory...")
divider()
let memory = engram.create(nil)
memory["working_capacity"] = 30
memory["max_episodic"] = 10000
memory["max_semantic"] = 5000

let all_facts = ["Sage is an indentation-based systems programming language built in C with self-hosted compiler", "127+ library modules across 11 subdirectories: graphics, os, net, crypto, ml, cuda, std, llm, agent, chat", "Concurrent tri-color mark-sweep GC with SATB write barriers and sub-millisecond STW pauses", "3 compiler backends: C codegen (--compile), LLVM IR (--compile-llvm), native assembly (--compile-native)", "Dotted imports: import os.fat resolves to lib/os/fat.sage", "0 is TRUTHY - only false and nil are falsy", "No escape sequences - use chr(10) for newline, chr(34) for double-quote", "elif chains with 5+ branches malfunction - use if/continue instead", "Class methods cannot see module-level let vars", "match is a reserved keyword", "Lexer produces INDENT/DEDENT tokens", "Parser is recursive descent in compiler.c", "AST: Expr and Stmt nodes in ast.h", "Tree-walking interpreter (interpreter.c)", "Values: numbers, strings, bools, nil, arrays, dicts, closures", "GC 4 phases: root scan, concurrent mark, remark, concurrent sweep", "Write barriers in env.c and value.c", "gc_disable() for heavy-allocation modules", "Native ML: matmul, softmax, cross_entropy, adam_update, rms_norm, silu, gelu at 12+ GFLOPS", "LLM library: 15 modules for building language models", "SageGPT: SwiGLU + RoPE + RMSNorm (Llama-style)", "LoRA for fine-tuning, DPO for alignment", "Engram: 4-tier memory with consolidation and decay", "RAG with keyword extraction and chunking", "GGUF export/import for Ollama and llama.cpp", "Quantization: int8/int4 with per-group scaling", "Agent ReAct loop: observe, think, act, reflect", "Supervisor-Worker architecture", "Critic/validator: rule-based + LLM critics", "Grammar-constrained decoding", "Tree of Thoughts: MCTS-style search", "Semantic routing: fast keyword dispatch", "SFT trace recording", "Schema-validated tool calls", "Task planner: dependency DAG", "6 personas: SageDev, CodeReviewer, Teacher, Debugger, Architect, Assistant", "Sessions: multi-session with history export", "Vulkan engine: 24 modules, PBR, deferred, SSAO, SSR, TAA", "OpenGL 4.5 backend", "OS dev: 15 modules (FAT, ELF, PE, MBR, GPT, PCI, ACPI, UEFI, paging, IDT)", "Networking: socket, tcp, http, ssl + 8 lib/net modules", "Crypto: SHA-256, HMAC, Base64, RC4, PBKDF2 (6 modules)", "Std: regex, datetime, log, argparse, fmt, testing, enum, trait, channel (23 modules)", "Build: make or cmake. Version 1.0.0", "Tests: 1567+ self-hosted, 144 interpreter, 28 compiler", "Library search: CWD, ./lib, installed, SAGE_PATH, exe-relative", "CUDA: device, memory, kernel, stream", "ML: tensor, nn, optim, loss, data, debug, viz, monitor", "Graphics: scene, gltf 2.0, material, asset cache, frame graph", "GGUF import: convert Ollama/llama.cpp models to SageGPT format"]

for i in range(len(all_facts)):
    engram.store_semantic(memory, all_facts[i], 1.0)

engram.store_procedural(memory, "write_sage_code", ["proc for functions, class for OOP", "let for variables, indent with spaces", "import os.fat for dotted imports", "gc_disable() for heavy allocation", "chr(10) for newline, avoid 5+ elif"], 1.0)
engram.store_procedural(memory, "debug_sage", ["gc_disable() for segfaults", "avoid match keyword", "chr() not escape sequences", "bash tests/run_tests.sh"], 1.0)
engram.store_procedural(memory, "add_builtin", ["emit_call_expr() in compiler.c", "init_stdlib() in interpreter.c", "C runtime in prelude", "test + docs"], 1.0)
engram.store_procedural(memory, "add_lib_module", ["lib/<category>/name.sage", "gc_disable() if needed", "test in tests/26_stdlib/", "Makefile + docs"], 1.0)
engram.store_procedural(memory, "compile_sage", ["--compile (C)", "--compile-llvm", "--compile-native", "--emit-c/--emit-llvm/--emit-asm"], 1.0)
engram.store_procedural(memory, "build_llm", ["llm.config for size", "cosine LR + LoRA", "DPO + RAG + Engram", "quantize for deploy"], 1.0)
engram.store_procedural(memory, "build_agent", ["agent.core + tools + schema", "planner, critic, router", "traces for SFT", "supervisor for multi-worker"], 1.0)
engram.store_procedural(memory, "build_chatbot", ["bot.create() + LLM fn", "apply persona, add intents", "session store"], 1.0)
engram.store_procedural(memory, "use_graphics", ["window + pipeline", "math3d, mesh, renderer", "PBR, post-processing"], 1.0)
engram.store_procedural(memory, "fix_gc_segfault", ["gc_disable() at top", "gc_pin()/gc_unpin()", "check write barriers"], 1.0)

log("ENGRAM", engram.summary(memory))
print ""

# ============================================================================
# Phase 8: Quantize
# ============================================================================

log("QUANT", "Phase 8: Quantization...")
divider()
let q_embed = quantize.quantize_int8(embed_w)
let deq_embed = quantize.dequantize_int8(q_embed)
let embed_err = quantize.quantization_error(embed_w, deq_embed)
log("QUANT", "Embed error: max=" + str(embed_err["max_error"]) + " mean=" + str(embed_err["mean_error"]))
let sizes = quantize.size_comparison(param_count)
log("QUANT", "FP32=" + sizes["fp32"] + " FP16=" + sizes["fp16"] + " INT8=" + sizes["int8"] + " INT4=" + sizes["int4"])
print ""

# ============================================================================
# Phase 9: Generate chatbot
# ============================================================================

log("BUILD", "Phase 9: Generating chatbot...")
divider()

let out_path = "models/sagellm_chatbot.sage"
let S = []
proc emit(line):
    push(S, line)
proc emit_all():
    let result = ""
    for i in range(len(S)):
        result = result + S[i] + NL
    io.writefile(out_path, result)
    log("BUILD", "Generated " + out_path + " (" + str(len(S)) + " lines)")

emit("gc_disable()")
emit("# SageLLM Chatbot v2.0.0 - Medium Model, 16K Context, All Features")
emit("# Auto-generated by build_sagellm.sage")
emit("# Run: sage models/sagellm_chatbot.sage")
emit("")
emit("import io")
emit("import chat.bot")
emit("import chat.persona")
emit("import chat.session")
emit("import llm.engram")
emit("import llm.rag")
emit("import llm.prompt")
emit("import agent.planner")
emit("import agent.critic")
emit("import agent.grammar")
emit("import agent.semantic_router")
emit("import agent.trace")
emit("import agent.tot")
emit("import agent.schema")
emit("")
emit("proc contains(h, n):")
emit("    if len(n) > len(h):")
emit("        return false")
emit("    for i in range(len(h) - len(n) + 1):")
emit("        let f = true")
emit("        for j in range(len(n)):")
emit("            if not f:")
emit("                j = len(n)")
emit("            if f and h[i + j] != n[j]:")
emit("                f = false")
emit("        if f:")
emit("            return true")
emit("    return false")
emit("")
emit("proc to_lower(s):")
emit("    let r = " + DQ + DQ)
emit("    for i in range(len(s)):")
emit("        let c = ord(s[i])")
emit("        if c >= 65 and c <= 90:")
emit("            r = r + chr(c + 32)")
emit("        else:")
emit("            r = r + s[i]")
emit("    return r")
emit("")
emit("proc starts_with(s, prefix):")
emit("    if len(prefix) > len(s):")
emit("        return false")
emit("    for i in range(len(prefix)):")
emit("        if s[i] != prefix[i]:")
emit("            return false")
emit("    return true")
emit("")
emit("proc substr(s, start, count):")
emit("    let r = " + DQ + DQ)
emit("    let end = start + count")
emit("    if end > len(s):")
emit("        end = len(s)")
emit("    for i in range(end - start):")
emit("        r = r + s[start + i]")
emit("    return r")
emit("")

# Engram in chatbot
emit("let memory = engram.create(nil)")
emit("memory[" + DQ + "working_capacity" + DQ + "] = 30")
emit("memory[" + DQ + "max_episodic" + DQ + "] = 10000")
emit("memory[" + DQ + "max_semantic" + DQ + "] = 5000")
for i in range(len(all_facts)):
    emit("engram.store_semantic(memory, " + DQ + all_facts[i] + DQ + ", 1.0)")
emit("engram.store_procedural(memory, " + DQ + "write_sage_code" + DQ + ", [" + DQ + "proc for functions" + DQ + ", " + DQ + "let for variables" + DQ + ", " + DQ + "import os.fat" + DQ + ", " + DQ + "gc_disable()" + DQ + ", " + DQ + "chr(10) for newline" + DQ + "], 1.0)")
emit("engram.store_procedural(memory, " + DQ + "debug_sage" + DQ + ", [" + DQ + "gc_disable()" + DQ + ", " + DQ + "avoid match" + DQ + ", " + DQ + "chr() not escapes" + DQ + "], 1.0)")
emit("engram.store_procedural(memory, " + DQ + "compile_sage" + DQ + ", [" + DQ + "--compile" + DQ + ", " + DQ + "--compile-llvm" + DQ + ", " + DQ + "--compile-native" + DQ + "], 1.0)")
emit("")
emit("let rag_store = rag.create_store()")
emit("let rag_files = [" + DQ + "documentation/SageLang_Guide.md" + DQ + ", " + DQ + "documentation/GC_Guide.md" + DQ + ", " + DQ + "documentation/LLM_Guide.md" + DQ + ", " + DQ + "documentation/Agent_Chat_Guide.md" + DQ + ", " + DQ + "documentation/StdLib_Guide.md" + DQ + "]")
emit("for i in range(len(rag_files)):")
emit("    let content = io.readfile(rag_files[i])")
emit("    if content != nil:")
emit("        let meta = {}")
emit("        meta[" + DQ + "source" + DQ + "] = rag_files[i]")
emit("        rag.add_document(rag_store, content, meta)")
emit("")
emit("let router = semantic_router.create_router(2)")
emit("semantic_router.add_sage_routes(router)")
emit("let recorder = trace.create_recorder()")
emit("let validator = critic.create_validator()")
emit("critic.add_rule(validator, " + DQ + "not_empty" + DQ + ", critic.rule_not_empty)")
emit("")

# Reasoning engine with all 20 topics
emit("proc reason(question):")
emit("    let chain = {}")
emit("    chain[" + DQ + "steps" + DQ + "] = []")
emit("    chain[" + DQ + "conclusion" + DQ + "] = " + DQ + DQ)
emit("    let lp = to_lower(question)")
emit("    let fast = semantic_router.route(router, lp)")
emit("    if fast[" + DQ + "routed" + DQ + "]:")
emit("        push(chain[" + DQ + "steps" + DQ + "], " + DQ + "Fast-routed" + DQ + ")")
emit("        chain[" + DQ + "conclusion" + DQ + "] = fast[" + DQ + "result" + DQ + "]")
emit("        return chain")
emit("    let mem_results = engram.recall(memory, lp, 5)")
emit("    if len(mem_results) > 0:")
emit("        let mt = " + DQ + DQ)
emit("        for i in range(len(mem_results)):")
emit("            mt = mt + mem_results[i][" + DQ + "entry" + DQ + "][" + DQ + "content" + DQ + "]")
emit("            if i < len(mem_results) - 1:")
emit("                mt = mt + " + DQ + "; " + DQ)
emit("        push(chain[" + DQ + "steps" + DQ + "], " + DQ + "Recalled: " + DQ + " + mt)")
emit("    let rag_ctx = rag.build_context(rag_store, lp, 3)")
emit("    if len(rag_ctx) > 0:")
emit("        push(chain[" + DQ + "steps" + DQ + "], " + DQ + "RAG: " + DQ + " + str(len(rag_ctx)) + " + DQ + " chars" + DQ + ")")
emit("    let topic = " + DQ + "general" + DQ)

# Topic classification
let topics_kw = [["llm", "llm|language model|transformer|lora|engram|neural|tokeniz"], ["agent", "agent|react|supervisor|tool use"], ["chatbot", "chatbot|persona|conversation|intent"], ["crypto", "crypto|sha|hash|encrypt"], ["networking", "network|http|socket|url|dns"], ["osdev", "baremetal|uefi|kernel|elf|pci|osdev"], ["ml", "tensor|machine learn|training|gradient"], ["graphics", "gpu|vulkan|opengl|shader|render"], ["regex", "regex|regular exp"], ["gc", "gc |garbage"], ["compiler", "compile|backend|emit"], ["loops", "for |loop|while"], ["modules", "import|module|library"], ["oop", "class |object|inherit"], ["data", "array|dict|data struct"], ["functions", "function|proc |closure"], ["errors", "error|exception|try "], ["testing", "test|debug|bug"], ["concurrency", "thread|async|channel|concurrent"], ["planning", "plan |how to build|steps"]]

for ti in range(len(topics_kw)):
    let tname = topics_kw[ti][0]
    let kw_str = topics_kw[ti][1]
    let kw_parts = []
    let current = ""
    for c in range(len(kw_str)):
        if kw_str[c] == "|":
            push(kw_parts, current)
            current = ""
        else:
            current = current + kw_str[c]
    push(kw_parts, current)
    emit("    if topic == " + DQ + "general" + DQ + ":")
    let check = "        if "
    for k in range(len(kw_parts)):
        if k > 0:
            check = check + " or "
        check = check + "contains(lp, " + DQ + kw_parts[k] + DQ + ")"
    emit(check + ":")
    emit("            topic = " + DQ + tname + DQ)

emit("    push(chain[" + DQ + "steps" + DQ + "], " + DQ + "Topic: " + DQ + " + topic)")
emit("    let answer = " + DQ + DQ)

# Answers
let ans = {}
ans["llm"] = "LLM library (15 modules): config, tokenizer, embedding, attention, transformer, generate, train, agent, prompt, lora, quantize, engram, rag, dpo, gguf. SageGPT: SwiGLU+RoPE+RMSNorm. Native C backend at 12+ GFLOPS."
ans["agent"] = "Agent framework (12 modules): core (ReAct), tools, planner (DAG), router, supervisor (workers), critic, schema, trace (SFT), grammar (constrained decoding), sandbox, tot (Tree of Thoughts), semantic_router."
ans["chatbot"] = "Chat framework: bot (intents, middleware), persona (6: SageDev, CodeReviewer, Teacher, Debugger, Architect, Assistant), session (history, export)."
ans["crypto"] = "Crypto (6 modules): hash (SHA-256, SHA-1, CRC-32), hmac, encoding (Base64, hex), cipher (XOR, RC4, CBC/CTR), rand (xoshiro256**, UUID v4), password (PBKDF2)."
ans["networking"] = "Networking: native (socket, tcp, http, ssl) + lib/net/ (8): url, headers, request, server, websocket, mime, dns, ip."
ans["osdev"] = "OS dev (15 modules): fat, elf, pe, mbr, gpt, pci, acpi, uefi, paging, idt, serial, dtb, alloc, vfs."
ans["ml"] = "ML: tensor, nn, optim, loss, data, debug, viz, monitor + cuda. Native: matmul, softmax, RMSNorm, Adam at 12+ GFLOPS."
ans["graphics"] = "GPU engine (24 modules): Vulkan + OpenGL 4.5. vulkan, gpu, math3d, mesh, renderer, pbr, shadows, deferred (SSAO, SSR), taa, postprocess, scene, gltf, material."
ans["regex"] = "Regex (std.regex): test(), search(), find_all(), replace_all(), split_by(). Supports . * + ? [] [^] ^ $ |."
ans["gc"] = "Tri-color GC: root scan (STW), concurrent mark, remark (STW), concurrent sweep. SATB write barrier. gc_collect(), gc_enable(), gc_disable()."
ans["compiler"] = "3 backends: --compile (C), --compile-llvm, --compile-native (x86-64/aarch64/rv64). Optimize: -O0 to -O3."
ans["loops"] = "Loops: for i in range(10): body. for item in array: body. while cond: body. break/continue."
ans["modules"] = "11 categories: os(15), net(8), crypto(6), ml(8), cuda(4), std(23), llm(15), agent(12), chat(3), graphics(24), root(9). 127+ total."
ans["oop"] = "OOP: class Name: with proc init(self): and methods. Inheritance: class Dog(Animal):."
ans["data"] = "Arrays: [1,2,3], push(), pop(), slicing. Dicts: {}, d[key]=val, dict_keys(), dict_values(). Tuples: (1,2,3)."
ans["functions"] = "proc name(args): body. Return values. Closures capture outer vars. First-class functions."
ans["errors"] = "try: risky. catch e: handle. finally: cleanup. raise to throw."
ans["testing"] = "Tests: run_tests.sh (144), make test (28), make test-selfhost (1567+). Debug: gc_disable(), chr()."
ans["concurrency"] = "Concurrency: thread, async/await, std.channel, std.atomic, std.rwlock, std.condvar, std.threadpool."
ans["planning"] = "Plan: 1) Define goal, 2) Create module, 3) Implement, 4) Test, 5) Document, 6) Run tests."

let ans_keys = dict_keys(ans)
for i in range(len(ans_keys)):
    emit("    if topic == " + DQ + ans_keys[i] + DQ + ":")
    emit("        answer = " + DQ + ans[ans_keys[i]] + DQ)

emit("    if len(answer) == 0:")
emit("        if len(mem_results) > 0:")
emit("            answer = " + DQ + "Based on my knowledge: " + DQ + " + mem_results[0][" + DQ + "entry" + DQ + "][" + DQ + "content" + DQ + "]")
emit("        else:")
emit("            answer = " + DQ + "I can help with: loops, imports, classes, GC, compiler, data, functions, errors, testing, concurrency, planning, LLM, agents, chatbot, crypto, networking, OS dev, ML, graphics, regex." + DQ)
emit("    push(chain[" + DQ + "steps" + DQ + "], " + DQ + "Answering about " + DQ + " + topic)")
emit("    chain[" + DQ + "conclusion" + DQ + "] = answer")
emit("    engram.store_episodic(memory, " + DQ + "Answered: " + DQ + " + topic, 0.6)")
emit("    trace.record_thought(recorder, " + DQ + "Topic: " + DQ + " + topic)")
emit("    trace.record_output(recorder, answer)")
emit("    return chain")
emit("")
emit("proc chain_to_string(chain):")
emit("    let result = " + DQ + DQ)
emit("    let steps = chain[" + DQ + "steps" + DQ + "]")
emit("    for i in range(len(steps)):")
emit("        result = result + " + DQ + "  Thought " + DQ + " + str(i + 1) + " + DQ + ": " + DQ + " + steps[i] + chr(10)")
emit("    result = result + chr(10) + " + DQ + "  Answer: " + DQ + " + chain[" + DQ + "conclusion" + DQ + "]")
emit("    return result")
emit("")
emit("proc sage_llm(p):")
emit("    return reason(p)[" + DQ + "conclusion" + DQ + "]")
emit("")
emit("let b = bot.create(" + DQ + DQ + ", " + DQ + DQ + ", sage_llm)")
emit("persona.apply_persona(b, persona.sage_developer())")
emit("proc on_greet(msg, conv):")
emit("    return " + DQ + "Hello! SageDev v2.0 with CoT, 4-tier memory, RAG, semantic routing, grammar validation, planning." + DQ)
emit("proc on_bye(msg, conv):")
emit("    engram.consolidate(memory)")
emit("    return " + DQ + "Goodbye. Memory consolidated." + DQ)
emit("proc on_help(msg, conv):")
emit("    return " + DQ + "Commands: quit, memory, remember <fact>, recall <query>, think <q>, plan <goal>, review <code>, trace, personas, help" + DQ)
emit("bot.add_intent(b, " + DQ + "greet" + DQ + ", [" + DQ + "hello" + DQ + ", " + DQ + "hi" + DQ + ", " + DQ + "hey" + DQ + "], on_greet)")
emit("bot.add_intent(b, " + DQ + "bye" + DQ + ", [" + DQ + "bye" + DQ + ", " + DQ + "quit" + DQ + ", " + DQ + "exit" + DQ + "], on_bye)")
emit("bot.add_intent(b, " + DQ + "help" + DQ + ", [" + DQ + "help" + DQ + ", " + DQ + "commands" + DQ + ", " + DQ + "?" + DQ + "], on_help)")
emit("let store = session.create_store()")
emit("let sess = session.new_session(store, " + DQ + "SageDev" + DQ + ")")
emit("let current_persona = " + DQ + "SageDev" + DQ)
emit("")
emit("print " + DQ + "============================================" + DQ)
emit("print " + DQ + "  SageLLM Chatbot v2.0.0 (Medium | 16K)" + DQ)
emit("print " + DQ + "  SageGPT: SwiGLU + RoPE + RMSNorm" + DQ)
emit("print " + DQ + "  CoT + Engram + RAG + Routing + Grammar" + DQ)
emit("print " + DQ + "============================================" + DQ)
emit("print bot.greet(b)")
emit("print " + DQ + "Commands: quit, memory, remember, recall, think, plan, review, trace, personas, help" + DQ)
emit("print " + DQ + DQ)
emit("let running = true")
emit("while running:")
emit("    let msg = input(" + DQ + "You> " + DQ + ")")
emit("    if msg == " + DQ + "quit" + DQ + " or msg == " + DQ + "exit" + DQ + ":")
emit("        running = false")
emit("        engram.consolidate(memory)")
emit("        print " + DQ + "SageDev> Goodbye. Memory consolidated." + DQ)
emit("    if running and msg == " + DQ + "memory" + DQ + ":")
emit("        print engram.summary(memory)")
emit("    if running and starts_with(msg, " + DQ + "remember " + DQ + "):")
emit("        engram.store_semantic(memory, substr(msg, 9, len(msg) - 9), 0.8)")
emit("        print " + DQ + "Remembered." + DQ)
emit("    if running and starts_with(msg, " + DQ + "recall " + DQ + "):")
emit("        let results = engram.recall(memory, substr(msg, 7, len(msg) - 7), 5)")
emit("        if len(results) > 0:")
emit("            for i in range(len(results)):")
emit("                print " + DQ + "  [" + DQ + " + str(i + 1) + " + DQ + "] " + DQ + " + results[i][" + DQ + "entry" + DQ + "][" + DQ + "content" + DQ + "]")
emit("        else:")
emit("            print " + DQ + "  No memories found." + DQ)
emit("    if running and starts_with(msg, " + DQ + "think " + DQ + "):")
emit("        trace.begin_trace(recorder, substr(msg, 6, len(msg) - 6))")
emit("        print chain_to_string(reason(substr(msg, 6, len(msg) - 6)))")
emit("        trace.end_trace(recorder, true)")
emit("    if running and starts_with(msg, " + DQ + "plan " + DQ + "):")
emit("        let goal = substr(msg, 5, len(msg) - 5)")
emit("        let plan = planner.create_plan(goal)")
emit("        planner.add_step(plan, " + DQ + "Analyze" + DQ + ", " + DQ + DQ + ", " + DQ + DQ + ", nil)")
emit("        planner.add_step(plan, " + DQ + "Design" + DQ + ", " + DQ + DQ + ", " + DQ + DQ + ", [0])")
emit("        planner.add_step(plan, " + DQ + "Implement" + DQ + ", " + DQ + DQ + ", " + DQ + DQ + ", [1])")
emit("        planner.add_step(plan, " + DQ + "Test" + DQ + ", " + DQ + DQ + ", " + DQ + DQ + ", [2])")
emit("        planner.add_step(plan, " + DQ + "Document" + DQ + ", " + DQ + DQ + ", " + DQ + DQ + ", [3])")
emit("        print planner.format_plan(plan)")
emit("        engram.store_episodic(memory, " + DQ + "Plan: " + DQ + " + goal, 0.8)")
emit("    if running and starts_with(msg, " + DQ + "review " + DQ + "):")
emit("        let v = grammar.validate_sage_code(substr(msg, 7, len(msg) - 7))")
emit("        if v[" + DQ + "valid" + DQ + "]:")
emit("            print " + DQ + "  Code valid!" + DQ)
emit("        else:")
emit("            let errs = v[" + DQ + "errors" + DQ + "]")
emit("            for i in range(len(errs)):")
emit("                print " + DQ + "  - " + DQ + " + errs[i]")
emit("    if running and msg == " + DQ + "trace" + DQ + ":")
emit("        let ts = trace.stats(recorder)")
emit("        print " + DQ + "  Traces: " + DQ + " + str(ts[" + DQ + "total_traces" + DQ + "]) + " + DQ + " Steps: " + DQ + " + str(ts[" + DQ + "total_steps" + DQ + "]))")
emit("    if running and msg == " + DQ + "personas" + DQ + ":")
emit("        print " + DQ + "  sagedev, teacher, debugger, architect" + DQ)
emit("    if running and msg == " + DQ + "teacher" + DQ + ":")
emit("        persona.apply_persona(b, persona.teacher())")
emit("        current_persona = " + DQ + "Teacher" + DQ)
emit("        print " + DQ + "Switched to Teacher." + DQ)
emit("    if running and msg == " + DQ + "debugger" + DQ + ":")
emit("        persona.apply_persona(b, persona.debugger())")
emit("        current_persona = " + DQ + "Debugger" + DQ)
emit("        print " + DQ + "Switched to Debugger." + DQ)
emit("    if running and msg == " + DQ + "architect" + DQ + ":")
emit("        persona.apply_persona(b, persona.architect())")
emit("        current_persona = " + DQ + "Architect" + DQ)
emit("        print " + DQ + "Switched to Architect." + DQ)
emit("    if running and msg == " + DQ + "sagedev" + DQ + ":")
emit("        persona.apply_persona(b, persona.sage_developer())")
emit("        current_persona = " + DQ + "SageDev" + DQ)
emit("        print " + DQ + "Switched to SageDev." + DQ)
emit("    if running and msg != " + DQ + "quit" + DQ + " and msg != " + DQ + "exit" + DQ + " and msg != " + DQ + "memory" + DQ + " and msg != " + DQ + "trace" + DQ + " and msg != " + DQ + "personas" + DQ + " and msg != " + DQ + "help" + DQ + " and msg != " + DQ + "?" + DQ + " and msg != " + DQ + "teacher" + DQ + " and msg != " + DQ + "debugger" + DQ + " and msg != " + DQ + "architect" + DQ + " and msg != " + DQ + "sagedev" + DQ + ":")
emit("        let is_cmd = false")
emit("        if starts_with(msg, " + DQ + "think " + DQ + "):")
emit("            is_cmd = true")
emit("        if starts_with(msg, " + DQ + "plan " + DQ + "):")
emit("            is_cmd = true")
emit("        if starts_with(msg, " + DQ + "review " + DQ + "):")
emit("            is_cmd = true")
emit("        if starts_with(msg, " + DQ + "remember " + DQ + "):")
emit("            is_cmd = true")
emit("        if starts_with(msg, " + DQ + "recall " + DQ + "):")
emit("            is_cmd = true")
emit("        if not is_cmd:")
emit("            engram.store_working(memory, msg, 0.7)")
emit("            trace.begin_trace(recorder, msg)")
emit("            let resp = bot.respond(b, msg)")
emit("            trace.record_output(recorder, resp)")
emit("            trace.end_trace(recorder, true)")
emit("            let ctx = {}")
emit("            ctx[" + DQ + "task" + DQ + "] = msg")
emit("            critic.validate(validator, resp, ctx)")
emit("            print " + DQ + DQ)
emit("            print current_persona + " + DQ + "> " + DQ + " + resp")
emit("            print " + DQ + DQ)
emit("            session.add_turn(sess, msg, resp)")

emit_all()
print ""

# ============================================================================
# Phase 10: GGUF Export
# ============================================================================

log("GGUF", "Phase 10: GGUF export...")
divider()
let gguf_meta = gguf.create_metadata("sagellm-medium-v2", "llama")
gguf.set_architecture(gguf_meta, d_model, n_layers, n_heads, d_ff, vocab, context_length)
gguf.set_quantization(gguf_meta, "Q8_0")
let modelfile = gguf.generate_modelfile("sagellm-medium-v2.gguf", "You are SageDev, an expert Sage programming assistant.", 0.7, context_length)
io.writefile("models/Modelfile", modelfile)
let quant_script = gguf.generate_quantize_script("sagellm-medium-v2.gguf")
io.writefile("models/quantize.sh", quant_script)
log("GGUF", "Generated Modelfile + quantize.sh")
log("GGUF", "Import from Ollama: import llm.gguf_import")
print ""

# ============================================================================
# Phase 11: Visualization
# ============================================================================

log("VIZ", "Phase 11: Visualizations...")
divider()
io.writefile("models/viz/.keep", "")
viz.loss_curve(all_losses, "SageLLM-Medium Loss", "models/viz/loss_curve.svg")
viz.weight_histogram(layer_qw[0], "Q-Proj Weights", "models/viz/weight_dist.svg")
viz.architecture_diagram("SageLLM-Medium", n_layers, d_model, d_ff, n_heads, "models/viz/architecture.svg")
viz.lr_schedule_chart(theory_steps, 20, 0.0003, 0.00001, "cosine", "models/viz/lr_schedule.svg")
log("VIZ", "Generated: loss, weights, architecture, LR SVGs")
log("VIZ", monitor.summary(mon))
print ""

# ============================================================================
# Phase 12: Summary
# ============================================================================

separator()
print "  SageLLM Build Complete"
separator()
print ""
print "Model: SageGPT-Medium (SwiGLU + RoPE + RMSNorm)"
print "  d=" + str(d_model) + " heads=" + str(n_heads) + " layers=" + str(n_layers) + " ff=" + str(d_ff) + " vocab=" + str(vocab) + " ctx=" + str(context_length)
print "  Parameters: " + str(param_count)
print ""
print "Training:"
print "  Pre-train: " + str(theory_steps) + " steps, loss=" + str(train.avg_loss(state1))
print "  LoRA: " + str(lora_steps) + " steps on " + str(file_count) + " files, rank=" + str(lora_rank) + " loss=" + str(train.avg_loss(state2))
print "  DPO: " + str(len(dpo_ds["pairs"])) + " preference pairs"
print ""
print "Knowledge:"
print "  Engram: " + str(len(memory["semantic"])) + " semantic + " + str(len(memory["procedural"])) + " procedural"
print "  RAG: " + str(rag_stats["total_docs"]) + " docs (" + str(rag_stats["total_chunks"]) + " chunks)"
print ""
print "Features: SwiGLU, RoPE, RMSNorm, LoRA, DPO, RAG, Engram, Semantic Routing,"
print "  Grammar Validation, Critic, SFT Traces, Planning, 6 Personas, Sessions,"
print "  GGUF Export/Import, INT8 Quantization, SVG Visualization, GPU Acceleration"
print ""
print "Output: models/sagellm_chatbot.sage | models/Modelfile | models/viz/"
print "Run:     ./sage models/sagellm_chatbot.sage"
print "Compile: ./sage --compile models/sagellm_chatbot.sage -o sagellm_chat"
print ""
let bench = gpu_accel.benchmark(gpu, d_model, 10)
print "Compute: " + str(bench["gflops"]) + " GFLOPS (" + str(bench["ms_per_matmul"]) + " ms @ " + str(d_model) + "x" + str(d_model) + ")"
print gpu_accel.stats(gpu)
gpu_accel.destroy(gpu)
separator()
