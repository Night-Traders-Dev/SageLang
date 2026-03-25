# SageLang LLM & Neural Network Guide

Build, train, fine-tune, and deploy language models from tiny test models to Llama-scale architectures, with a full agentic framework for tool use, chain-of-thought reasoning, and multi-agent orchestration.

## Architecture

```text
Application Layer:  Agent loops, chat interfaces, RAG pipelines
        |
Agent Framework:    lib/llm/agent (tools, memory, CoT, planning, teams)
        |
Generation:         lib/llm/generate (sampling, beam search, repetition penalty)
        |
Model:              lib/llm/transformer (blocks, norms, FFN)
        |                    |
Attention:          lib/llm/attention (MHA, KV cache, causal mask)
        |
Embeddings:         lib/llm/embedding (token, sinusoidal, RoPE)
        |
Tokenizer:          lib/llm/tokenizer (char, word, BPE)
        |
Training:           lib/llm/train (loops, LR schedules, loss)
Fine-tuning:        lib/llm/lora (low-rank adapters)
Compression:        lib/llm/quantize (int8, int4), lib/llm/turboquant (PolarQuant+QJL, 1-4 bit)
Config:             lib/llm/config (GPT-2, Llama, Mistral presets)
```

---

## Quick Start: Build a Tiny LLM

```sage
import llm.config
import llm.tokenizer
import llm.transformer

# 1. Configure a tiny model
let cfg = config.tiny()
print config.summary(cfg)

# 2. Create tokenizer
let tok = tokenizer.char_tokenizer()

# 3. Build the model
let model = transformer.create_model(cfg)
print "Parameters: ~" + config.param_count_str(cfg)
```

---

## Model Configurations (`llm.config`)

Predefined configs from ~1M to ~13B parameters:

| Config | Function | Params | Context | Layers | d_model |
|--------|----------|--------|---------|--------|---------|
| Tiny | `config.tiny()` | ~1M | 128 | 2 | 64 |
| Small | `config.small()` | ~10M | 256 | 4 | 128 |
| GPT-2 | `config.gpt2()` | ~124M | 1024 | 12 | 768 |
| GPT-2 Medium | `config.gpt2_medium()` | ~355M | 1024 | 24 | 1024 |
| GPT-2 Large | `config.gpt2_large()` | ~774M | 1024 | 36 | 1280 |
| Llama 7B | `config.llama_7b()` | ~7B | 4096 | 32 | 4096 |
| Llama 13B | `config.llama_13b()` | ~13B | 4096 | 40 | 5120 |
| Mistral 7B | `config.mistral_7b()` | ~7B | 32768 | 32 | 4096 |
| Phi-2 | `config.phi_2()` | ~2.7B | 2048 | 32 | 2560 |
| Agent Small | `config.agent_small()` | ~50M | 4096 | 8 | 512 |
| Agent Medium | `config.agent_medium()` | ~200M | 8192 | 16 | 1024 |

---

## Tokenization (`llm.tokenizer`)

```sage
import llm.tokenizer

# Character-level (simplest, for testing)
let ctok = tokenizer.char_tokenizer()
let ids = tokenizer.encode(ctok, "hello")     # [104, 101, 108, 108, 111]
let text = tokenizer.decode(ctok, ids)         # "hello"

# Word-level
let wtok = tokenizer.word_tokenizer()
tokenizer.build_vocab(wtok, corpus_text, 10000)
let wids = tokenizer.encode(wtok, "the quick brown fox")

# BPE (Byte Pair Encoding)
let bpe = tokenizer.bpe_tokenizer(8192)
tokenizer.train_bpe(bpe, training_text, 1000)
let bids = tokenizer.encode(bpe, "hello world")

# Utilities
let padded = tokenizer.pad_sequence(ids, 128, ctok["pad_id"])
let with_special = tokenizer.add_special(ctok, ids)  # [BOS] + ids + [EOS]
```

---

## Text Generation (`llm.generate`)

```sage
import llm.generate

# Greedy decoding
let next = generate.greedy(logits)

# Top-k sampling
let filtered = generate.top_k_filter(logits, 50)

# Top-p (nucleus) sampling
let nucleus = generate.top_p_filter(logits, 0.9)

# Temperature scaling
let hot = generate.apply_temperature(logits, 1.5)   # more creative
let cold = generate.apply_temperature(logits, 0.3)  # more focused

# Full generation loop
let gen_cfg = generate.creative_config()
gen_cfg["max_new_tokens"] = 200
let output_ids = generate.generate(my_model_fn, input_ids, gen_cfg, 42)
```

### Generation Presets

| Preset | Temperature | Top-K | Top-P | Use Case |
|--------|-------------|-------|-------|----------|
| `greedy_config()` | 1.0 | - | - | Deterministic, factual |
| `precise_config()` | 0.3 | 10 | 0.5 | Code, structured output |
| `create_gen_config()` | 1.0 | 50 | 0.9 | Balanced (default) |
| `creative_config()` | 1.2 | 100 | 0.95 | Stories, brainstorming |

---

## Training (`llm.train`)

```sage
import llm.train

let train_cfg = train.create_train_config()
train_cfg["learning_rate"] = 0.0003
train_cfg["batch_size"] = 4
train_cfg["epochs"] = 3
train_cfg["warmup_steps"] = 100
train_cfg["lr_schedule"] = "cosine"

# Prepare data
let examples = train.create_lm_examples(token_ids, seq_len)
let batches = train.batch_examples(examples, train_cfg["batch_size"])

# Training loop
let state = train.training_loop(train_cfg, train_step_fn, data_loader, num_batches, total_steps)
print "Final loss: " + str(train.avg_loss(state))
print "Best loss: " + str(state["best_loss"])
print "Perplexity: " + str(train.perplexity(train.avg_loss(state)))
```

---

## Agentic Framework (`llm.agent`)

### Creating an Agent with Tools

```sage
import llm.agent

let assistant = agent.create_agent("assistant", "You are a helpful AI assistant.")

# Register tools
proc search_fn(args):
    return "Results for: " + str(args)

proc calc_fn(args):
    return args["a"] + args["b"]

agent.add_tool(assistant, "search", "Search the web", search_fn)
agent.add_tool(assistant, "calculate", "Do math", calc_fn)

# Call a tool
let result = agent.call_tool(assistant["toolbox"], "calculate", {"a": 3, "b": 4})
print result["result"]  # 7

# Build prompt with tool descriptions + memory
let prompt = agent.build_prompt(assistant, "What is 3 + 4?")
```

### Chain-of-Thought Reasoning

```sage
let chain = agent.create_reasoning_chain()
agent.add_thought(chain, "The user wants to know 3 + 4")
agent.add_action(chain, "calculate(3, 4)", 7)
agent.add_thought(chain, "The answer is 7")
agent.set_conclusion(chain, "3 + 4 = 7")
print agent.format_chain(chain)
```

### Memory System

```sage
let mem = agent.create_memory(20)
agent.add_fact(mem, "User prefers Python")
agent.add_short_term(mem, "Asked about sorting algorithms")
agent.add_long_term(mem, "user_name", "Alice")
print agent.memory_context(mem)
```

### Multi-Agent Teams

```sage
let team = agent.create_team("dev-team")

let planner = agent.create_agent("planner", "You plan tasks")
let coder = agent.create_agent("coder", "You write code")
let reviewer = agent.create_agent("reviewer", "You review code")

agent.add_agent(team, planner)
agent.add_agent(team, coder)
agent.add_agent(team, reviewer)
agent.set_coordinator(team, "planner")

agent.send_message(team, "planner", "coder", "Implement a sorting function")
print agent.team_summary(team)
```

### Planning

```sage
let plan = agent.create_plan("Build a web scraper")
agent.add_plan_step(plan, "Parse URL", "planner")
agent.add_plan_step(plan, "Fetch HTML", "coder")
agent.add_plan_step(plan, "Extract data", "coder")
agent.add_plan_step(plan, "Review output", "reviewer")

agent.advance_plan(plan, "URL parsed")
print agent.format_plan(plan)
print agent.plan_progress(plan)  # 0.25
```

---

## LoRA Fine-Tuning (`llm.lora`)

```sage
import llm.lora
import llm.config

let cfg = config.gpt2()
let lora_cfg = lora.create_lora_config(8, 16, lora.default_targets())

# default_targets() = ["q_proj", "v_proj"]
# all_attention_targets() = ["q_proj", "k_proj", "v_proj", "o_proj"]
# all_linear_targets() = adds FFN layers too

let model = transformer.create_model(cfg)
let lora_result = lora.apply_lora(model, lora_cfg)
print "Trainable: " + str(lora.trainable_params(lora_result))
print "Savings: " + str(lora.savings_ratio(lora_result, config.param_count(cfg)) * 100) + "%"

# After training, merge weights for deployment
let merged = lora.merge_weights(base_weight, adapter)
```

---

## Quantization (`llm.quantize`)

```sage
import llm.quantize

# Int8 quantization (4x compression)
let q8 = quantize.quantize_int8(weight_data)
let restored = quantize.dequantize_int8(q8)
let error = quantize.quantization_error(weight_data, restored)
print "RMSE: " + str(error["rmse"])
print "SNR: " + str(error["snr_db"]) + " dB"

# Int4 quantization (8x compression, per-group)
let q4 = quantize.quantize_int4(weight_data, 32)  # group_size=32

# Model size comparison
let sizes = quantize.size_comparison(config.param_count(config.llama_7b()))
print "FP32: " + sizes["fp32"]   # ~26 GB
print "FP16: " + sizes["fp16"]   # ~13 GB
print "Int8: " + sizes["int8"]   # ~6 GB
print "Int4: " + sizes["int4"]   # ~3 GB
```

---

## TurboQuant (`llm.turboquant`)

Near-optimal vector quantization based on Google Research's ICLR 2026 paper. Two-stage compression:

1. **Stage 1 — PolarQuant**: Random rotation (Walsh-Hadamard) + MSE-optimal scalar quantization per coordinate. Uses pre-computed codebooks for 1-4 bit widths.
2. **Stage 2 — QJL**: Quantized Johnson-Lindenstrauss 1-bit sign projection on the residual. Provides unbiased inner product estimation.

Key features:

- Data-oblivious (no training/calibration needed)
- Post-training quantization (no fine-tuning required)
- 3-bit achieves 6x KV cache memory reduction with zero accuracy loss
- Up to 8x speedup on attention scoring
- Near information-theoretic optimal distortion

```sage
import llm.turboquant

# Full quantization (MSE + QJL, unbiased inner products)
let q = turboquant.quantize(vector, 3)       # 3-bit
let r = turboquant.dequantize(q)

# MSE-only (for value vectors)
let q_mse = turboquant.quantize_mse(vector, 2)
let r_mse = turboquant.dequantize_mse(q_mse)

# KV Cache compression
let cache = turboquant.create_kv_cache(1024, 128, 3)
turboquant.cache_push(cache, key_vec, value_vec)
let key = turboquant.cache_get_key(cache, 0)
let val = turboquant.cache_get_value(cache, 0)
let stats = turboquant.cache_stats(cache)  # compression_ratio ~6x

# Analysis
let mse = turboquant.mse_distortion(original, reconstructed)
let ip_err = turboquant.inner_product_error(x, y, x_hat)
let bound = turboquant.theoretical_mse_bound(3)  # 0.0425

# Benchmark
let bench = turboquant.benchmark(128, 3, 100)
print turboquant.summary(bench)
```

---

## AutoResearch (`llm.autoresearch`)

Karpathy-style autonomous research loop (March 2026). Core concept: a **ratchet loop** that accumulates improvements — each accepted experiment becomes the new baseline, and rejected ones are discarded. Runs 100+ experiments overnight without human supervision.

```sage
import llm.autoresearch

# Create a research session
let ar = autoresearch.create(config, train_fn, eval_fn)

# Set the program (hyperparameter space to search)
autoresearch.set_program(ar, my_program)

# Add mutation strategies
autoresearch.add_strategy(ar, autoresearch.make_scale_strategy("lr", 0.5, 2.0))
autoresearch.add_strategy(ar, autoresearch.make_choice_strategy("optimizer", ["adam", "sgd", "adamw"]))
autoresearch.add_strategy(ar, autoresearch.make_perturb_strategy("dropout", 0.01))

# Run N experiments
let session = autoresearch.run(ar, session, 100)
print autoresearch.summary(session)
```

### Built-in Strategies

| Strategy | Factory | Description |
|----------|---------|-------------|
| Scale | `make_scale_strategy(key, lo, hi)` | Multiplicatively perturbs a numeric hyperparameter within [lo, hi] |
| Choice | `make_choice_strategy(key, options)` | Randomly samples from a discrete set of values |
| Perturb | `make_perturb_strategy(key, sigma)` | Adds Gaussian noise with standard deviation sigma |

### Convenience Bundles

```sage
# Default LLM hyperparameter strategies (lr, batch_size, dropout, warmup)
let strategies = autoresearch.llm_default_strategies()

# Architecture search strategies (layers, d_model, heads, d_ff)
let arch = autoresearch.architecture_strategies()
```

### Multi-Agent Collaboration

```sage
# Export research journal for sharing
let journal = autoresearch.export_journal(session)

# Import journal from another agent
autoresearch.import_journal(ar, journal)

# Merge results from multiple parallel sessions
let merged = autoresearch.merge_sessions(session_a, session_b)
```

### Safety Features

- **max_revert_streak**: Auto-resets the baseline after N consecutive rejections, preventing the ratchet from locking on a local optimum.
- **Secondary metrics** (Goodhart protection): Tracks auxiliary metrics alongside the primary objective so that optimizing one metric does not degrade others.

---

## Module Reference

| Module | Import | Key Functions |
|--------|--------|---------------|
| `config` | `import llm.config` | `tiny`, `gpt2`, `llama_7b`, `agent_small`, `param_count`, `summary` |
| `tokenizer` | `import llm.tokenizer` | `char_tokenizer`, `bpe_tokenizer`, `train_bpe`, `encode`, `decode`, `pad_sequence` |
| `embedding` | `import llm.embedding` | `create_embedding`, `lookup`, `sinusoidal_encoding`, `rope_frequencies`, `apply_rope` |
| `attention` | `import llm.attention` | `scaled_dot_product`, `create_mha`, `mha_forward`, `create_kv_cache`, `causal_mask` |
| `transformer` | `import llm.transformer` | `create_model`, `create_block`, `apply_layer_norm`, `apply_rms_norm`, `ffn_forward` |
| `generate` | `import llm.generate` | `generate`, `greedy`, `top_k_filter`, `top_p_filter`, `softmax`, `beam_search` |
| `train` | `import llm.train` | `training_loop`, `cosine_schedule`, `cross_entropy_loss`, `perplexity`, `create_lm_examples` |
| `agent` | `import llm.agent` | `create_agent`, `add_tool`, `call_tool`, `build_prompt`, `create_team`, `send_message`, `create_plan` |
| `prompt` | `import llm.prompt` | `format_chatml`, `format_llama`, `few_shot`, `cot_prompt`, `truncate_history`, `render_template` |
| `lora` | `import llm.lora` | `create_adapter`, `lora_forward`, `apply_lora`, `merge_weights`, `trainable_params` |
| `quantize` | `import llm.quantize` | `quantize_int8`, `quantize_int4`, `dequantize_int8`, `quantization_error`, `size_comparison` |
| `engram` | `import llm.engram` | `create`, `store_working`, `store_semantic`, `recall`, `consolidate`, `build_context`, `summary` |
| `rag` | `import llm.rag` | `create_store`, `add_document`, `retrieve`, `build_context`, `rag_prompt`, `summarize_extractive` |
| `dpo` | `import llm.dpo` | `simple_dpo_loss`, `batch_dpo_loss`, `orpo_loss`, `sage_code_preferences`, `create_reward_model` (lambda config field, preferences returned as list, reward model uses array storage) |
| `gguf` | `import llm.gguf` | `export_metadata`, `create_modelfile`, `build_tensor_list`, `sage_to_gguf_config`, `quant_types`, `estimate_size` |
| `gguf_import` | `import llm.gguf_import` | `import_gguf`, `parse_header`, `read_metadata`, `extract_config`, `load_weights`, `dequantize_q4_0`, `dequantize_q8_0`, `convert_to_sagegpt`, `supported_architectures` |
| `turboquant` | `import llm.turboquant` | `quantize`, `dequantize`, `quantize_mse`, `dequantize_mse`, `create_kv_cache`, `cache_push`, `cache_get_key`, `cache_get_value`, `cache_stats`, `mse_distortion`, `inner_product_error`, `theoretical_mse_bound`, `benchmark`, `summary` |
| `gpu_accel` | `import ml.gpu_accel` | `create_context`, `matmul`, `add`, `rms_norm`, `silu`, `softmax`, `transformer_layer_forward`, `model_forward`, `train_step` |

## Ollama / llama.cpp Export

Export trained models to GGUF format for use with Ollama and llama.cpp:

```bash
sage models/export_ollama.sage
```

Generates:
- `model.gguf` — GGUF v3 metadata (llama-compatible architecture)
- `Modelfile` — Ollama config with system prompt, parameters, ChatML template
- `convert.sh` — Quantization script (F32/F16/Q8_0/Q4_K_M/Q2_K)

```bash
# Load into Ollama
cd models/export && ollama create sagellm -f Modelfile
ollama run sagellm

# Use with llama.cpp directly
llama-cli -m model.gguf -p "Write a Sage function"
llama-server -m model.gguf --port 8080
```

## GGUF Import (`llm.gguf_import`)

Import models from Ollama and llama.cpp into SageGPT format for native inference and fine-tuning:

```sage
import llm.gguf_import

# Import a GGUF model file
let model = gguf_import.import_gguf("path/to/model.gguf")
print model["config"]      # extracted model configuration
print model["weights"]     # converted weight tensors

# Step-by-step import
let header = gguf_import.parse_header("model.gguf")
let meta = gguf_import.read_metadata("model.gguf")
let cfg = gguf_import.extract_config(meta)
let weights = gguf_import.load_weights("model.gguf", header)

# Dequantize quantized weights
let fp32_weights = gguf_import.dequantize_q4_0(weights["layer.0.attn"])
let fp32_w2 = gguf_import.dequantize_q8_0(weights["layer.0.ffn"])

# Convert to SageGPT native format
let sage_model = gguf_import.convert_to_sagegpt(weights, cfg)

# Check supported architectures
let archs = gguf_import.supported_architectures()
# ["llama", "gpt2", "gemma", "phi", "qwen2", "mistral"]
```

### Supported Architectures

| Architecture | GGUF Key | Notes |
|-------------|----------|-------|
| Llama | `llama` | Llama 2/3, Code Llama, Vicuna |
| GPT-2 | `gpt2` | GPT-2 family |
| Gemma | `gemma` | Google Gemma models |
| Phi | `phi` | Microsoft Phi-2/3 |
| Qwen2 | `qwen2` | Alibaba Qwen2 family |
| Mistral | `mistral` | Mistral 7B, Mixtral |

---

## GPU-Accelerated ML (`ml.gpu_accel`)

Offload training and inference operations to the GPU with automatic CPU fallback. Supports backend targets: `"gpu"`, `"cpu"`, `"npu"`, `"tpu"`, and `"auto"` (auto-selects best available: GPU > CPU). When no GPU is present, all operations fall back transparently to `ml_native` (CPU) implementations.

```sage
import ml.gpu_accel

# Create a GPU acceleration context ("auto" selects best available backend)
let ctx = gpu_accel.create("auto")
print ctx["backend"]   # "vulkan", "opengl", or "cpu"

# GPU-aware matrix operations (automatic CPU fallback)
let C = gpu_accel.matmul(ctx, A, B)
let sum = gpu_accel.add(ctx, X, Y)

# GPU-aware normalization and activations
let normed = gpu_accel.rms_norm(ctx, hidden, weights, 1e-6)
let activated = gpu_accel.silu(ctx, normed)
let probs = gpu_accel.softmax(ctx, logits)

# Transformer layer forward pass (fully GPU-accelerated)
let output = gpu_accel.transformer_layer_forward(ctx, input, layer_weights)

# Full model forward pass
let logits = gpu_accel.model_forward(ctx, token_ids, model_weights)

# Loss computation
let loss = gpu_accel.cross_entropy(ctx, logits, targets)

# GPU-accelerated training step
let train_loss = gpu_accel.train_step(ctx, model, batch, learning_rate)

# Benchmark backends
gpu_accel.benchmark(ctx, 512)
```

### GLSL Compute Shaders

The GPU backend uses specialized GLSL compute shaders for each operation:

| Operation | Shader | Notes |
|-----------|--------|-------|
| Matrix multiply | `matmul.comp` | Tiled workgroups, shared memory |
| Softmax | `softmax.comp` | Numerically stable (max subtraction) |
| SiLU | `silu.comp` | Fused multiply-sigmoid |
| RMS Norm | `rmsnorm.comp` | Parallel reduction |

All operations detect GPU availability at context creation and fall back to CPU implementations transparently. No code changes needed between GPU and CPU execution paths.

---

## AI Builder

The interactive AI builder (`models/ai_builder.sage`) guides you through the full pipeline:

```bash
sage models/ai_builder.sage
```

12-phase pipeline (v2.0):

1. Data collection (entire codebase, 153+ source files, ~1.6M chars)
2. Model configuration (medium: d=128, 4 layers, 4 heads, d_ff=512, vocab=256, 16K context)
3. Tokenizer selection (char, BPE, word-level)
4. Pre-training (200 steps with native C backend)
5. LoRA fine-tuning (rank-16, 100 steps on domain data)
6. DPO alignment with preference pairs
7. RAG document store indexing
8. Engram persistent memory (50+ facts)
9. INT8 quantization
10. Chatbot generation with persona selection
11. GGUF export (Ollama/llama.cpp compatible)
12. SVG visualization of model architecture

The generated chatbot (`models/sagellm_chatbot.sage`) is self-contained (no module imports) and compiles to a native binary with either backend:

```bash
# C backend
sage --compile models/sagellm_chatbot.sage -o sagellm_chatbot

# LLVM IR backend
sage --compile-llvm models/sagellm_chatbot.sage -o sagellm_chatbot
```

---

## Known Issues

**LLVM backend: do not modify for-loop variables to fake a break.**
The LLVM backend does not support mutating the loop variable to exit early. Use `break` instead:

```sage
# WRONG — does not work under --compile-llvm
for j in range(len(arr)):
    if arr[j] == target:
        j = len(arr)   # attempting to force loop exit

# CORRECT
for j in range(len(arr)):
    if arr[j] == target:
        break
```
