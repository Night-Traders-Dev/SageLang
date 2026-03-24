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
Compression:        lib/llm/quantize (int8, int4)
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
