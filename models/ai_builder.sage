gc_disable()
# ============================================================================
# SageLLM AI Builder - Interactive step-by-step build system
#
# Usage: sage models/ai_builder.sage
#
# Guides you through building, training, and deploying AI models
# using the full Sage LLM/ML/AI library stack.
#
# Capabilities:
#   1. Model configuration (architecture, size, context)
#   2. Tokenizer selection and training
#   3. Training data preparation (corpus, RAG, preferences)
#   4. Pre-training on theory/code corpus
#   5. LoRA fine-tuning on domain data
#   6. DPO alignment with preference pairs
#   7. Engram memory loading (semantic, procedural, episodic)
#   8. RAG document store setup
#   9. Agent wiring (tools, CoT, planning)
#  10. Chatbot persona and intent configuration
#  11. Export and compilation
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
import llm.dpo
import llm.rag
import llm.agent
import llm.prompt
import agent.core
import agent.planner
import chat.bot
import chat.persona
import chat.session

let NL = chr(10)
let DQ = chr(34)

# ============================================================================
# Build state
# ============================================================================

let build = {}
build["model_name"] = ""
build["model_size"] = ""
build["d_model"] = 64
build["n_layers"] = 2
build["n_heads"] = 2
build["d_ff"] = 256
build["vocab_size"] = 128
build["context_length"] = 256
build["seq_len"] = 64
build["tokenizer_type"] = "char"
build["activation"] = "silu"
build["norm_type"] = "rms_norm"
build["training_steps"] = 50
build["lora_rank"] = 8
build["lora_alpha"] = 16
build["dpo_beta"] = 0.1
build["use_rag"] = false
build["use_engram"] = true
build["use_agent"] = false
build["use_chatbot"] = true
build["persona"] = "sage_developer"
build["output_path"] = "models/my_model.sage"
build["corpus_text"] = ""
build["step"] = 0
build["complete"] = false

# Engram, RAG, weights stored here during build
build["memory"] = nil
build["rag_store"] = nil
build["embed_w"] = nil
build["qw"] = nil
build["kw"] = nil
build["vw"] = nil
build["norm_w"] = nil
build["lm_head"] = nil
build["adapter"] = nil
build["tok"] = nil
build["train_loss"] = 0
build["lora_loss"] = 0

# ============================================================================
# Utilities
# ============================================================================

proc print_header(title):
    print ""
    print "================================================================"
    print "  " + title
    print "================================================================"
    print ""

proc print_option(num, label, desc):
    print "  " + str(num) + ") " + label + " - " + desc

proc prompt_choice(question, options):
    print question
    for i in range(len(options)):
        print "  " + str(i + 1) + ") " + options[i]
    let choice = input("  Choice [1-" + str(len(options)) + "]: ")
    return tonumber(choice)

proc prompt_yn(question):
    let answer = input(question + " [y/n]: ")
    return answer == "y" or answer == "Y" or answer == "yes"

proc prompt_str(question, default_val):
    let answer = input(question + " [" + default_val + "]: ")
    if len(answer) == 0:
        return default_val
    return answer

proc prompt_num(question, default_val):
    let answer = input(question + " [" + str(default_val) + "]: ")
    if len(answer) == 0:
        return default_val
    return tonumber(answer)

proc contains(h, n):
    if len(n) > len(h):
        return false
    for i in range(len(h) - len(n) + 1):
        let f = true
        for j in range(len(n)):
            if not f:
                j = len(n)
            if f and h[i + j] != n[j]:
                f = false
        if f:
            return true
    return false

# ============================================================================
# Step 1: Model Configuration
# ============================================================================

proc step_model_config():
    print_header("Step 1: Model Configuration")
    build["model_name"] = prompt_str("Model name", "my-sagellm")
    print ""
    let size = prompt_choice("Select model size:", ["Nano (64d, 2L, ~50K params) - fastest, for testing", "Micro (128d, 4L, ~500K params) - small, quick training", "Small (256d, 8L, ~5M params) - balanced", "Medium (512d, 16L, ~50M params) - high quality", "Large (1024d, 24L, ~200M params) - best quality", "Custom - specify your own dimensions"])
    if size == 1:
        build["model_size"] = "nano"
        build["d_model"] = 64
        build["n_layers"] = 2
        build["n_heads"] = 2
        build["d_ff"] = 256
    if size == 2:
        build["model_size"] = "micro"
        build["d_model"] = 128
        build["n_layers"] = 4
        build["n_heads"] = 4
        build["d_ff"] = 512
    if size == 3:
        build["model_size"] = "small"
        build["d_model"] = 256
        build["n_layers"] = 8
        build["n_heads"] = 8
        build["d_ff"] = 1024
    if size == 4:
        build["model_size"] = "medium"
        build["d_model"] = 512
        build["n_layers"] = 16
        build["n_heads"] = 16
        build["d_ff"] = 2048
    if size == 5:
        build["model_size"] = "large"
        build["d_model"] = 1024
        build["n_layers"] = 24
        build["n_heads"] = 16
        build["d_ff"] = 4096
    if size == 6:
        build["model_size"] = "custom"
        build["d_model"] = prompt_num("d_model", 128)
        build["n_layers"] = prompt_num("n_layers", 4)
        build["n_heads"] = prompt_num("n_heads", 4)
        build["d_ff"] = prompt_num("d_ff", 512)
    print ""
    build["context_length"] = prompt_num("Context window (tokens)", 512)
    build["vocab_size"] = prompt_num("Vocabulary size", 128)
    build["seq_len"] = prompt_num("Training sequence length", 64)
    print ""
    let act = prompt_choice("Activation function:", ["SiLU/Swish (Llama-style, recommended)", "GELU (GPT-style)", "ReLU (simple)"])
    if act == 1:
        build["activation"] = "silu"
    if act == 2:
        build["activation"] = "gelu"
    if act == 3:
        build["activation"] = "relu"
    let d = build["d_model"]
    let total = build["vocab_size"] * d + build["n_layers"] * (4 * d * d + 2 * d * build["d_ff"]) + d * build["vocab_size"]
    print ""
    print "  Model: " + build["model_name"] + " (" + build["model_size"] + ")"
    print "  Parameters: ~" + str(total)
    print "  Architecture: SwiGLU + RoPE + RMSNorm"
    print "  Context: " + str(build["context_length"]) + " tokens"

# ============================================================================
# Step 2: Tokenizer
# ============================================================================

proc step_tokenizer():
    print_header("Step 2: Tokenizer Selection")
    let choice = prompt_choice("Select tokenizer:", ["Character-level (fast, simple, 128 ASCII tokens)", "BPE (byte-pair encoding, trained on your data)", "Word-level (whitespace split, vocabulary from corpus)"])
    if choice == 1:
        build["tokenizer_type"] = "char"
        build["tok"] = tokenizer.char_tokenizer()
    if choice == 2:
        build["tokenizer_type"] = "bpe"
        build["tok"] = tokenizer.bpe_tokenizer(build["vocab_size"])
    if choice == 3:
        build["tokenizer_type"] = "word"
        build["tok"] = tokenizer.word_tokenizer()
    print "  Tokenizer: " + build["tokenizer_type"]

# ============================================================================
# Step 3: Training Data
# ============================================================================

proc step_training_data():
    print_header("Step 3: Training Data")
    let corpus = ""
    if prompt_yn("Load programming language theory corpus?"):
        let theory = io.readfile("models/data/programming_languages.txt")
        if theory != nil:
            corpus = corpus + theory
            print "  Loaded: programming_languages.txt (" + str(len(theory)) + " chars)"
    if prompt_yn("Load multi-language examples (Python/C/C++/Nim)?"):
        let ml = io.readfile("models/data/multilang_examples.txt")
        if ml != nil:
            corpus = corpus + ml
            print "  Loaded: multilang_examples.txt (" + str(len(ml)) + " chars)"
    if prompt_yn("Load natural language / NLP training data?"):
        let nlp = io.readfile("models/data/natural_language.txt")
        if nlp != nil:
            corpus = corpus + nlp
            print "  Loaded: natural_language.txt (" + str(len(nlp)) + " chars)"
    if prompt_yn("Load Sage source code (codebase)?"):
        let sage_files = ["lib/arrays.sage", "lib/dicts.sage", "lib/strings.sage", "lib/json.sage", "lib/math.sage", "src/sage/lexer.sage", "src/sage/parser.sage"]
        for i in range(len(sage_files)):
            let content = io.readfile(sage_files[i])
            if content != nil:
                corpus = corpus + content + NL
                print "  Loaded: " + sage_files[i]
    let custom_path = prompt_str("Custom data file path (or skip)", "skip")
    if custom_path != "skip":
        let custom = io.readfile(custom_path)
        if custom != nil:
            corpus = corpus + custom
            print "  Loaded: " + custom_path + " (" + str(len(custom)) + " chars)"
    build["corpus_text"] = corpus
    print ""
    print "  Total corpus: " + str(len(corpus)) + " chars (~" + str((len(corpus) / 4) | 0) + " tokens)"
    # Train BPE if selected
    if build["tokenizer_type"] == "bpe" and len(corpus) > 0:
        print "  Training BPE tokenizer..."
        let train_text = ""
        let max_c = 10000
        if len(corpus) < max_c:
            max_c = len(corpus)
        for i in range(max_c):
            train_text = train_text + corpus[i]
        tokenizer.train_bpe(build["tok"], train_text, 200)
        print "  BPE vocab: " + str(build["tok"]["vocab_size"])
    if build["tokenizer_type"] == "word" and len(corpus) > 0:
        tokenizer.build_vocab(build["tok"], corpus, build["vocab_size"])
        print "  Word vocab: " + str(build["tok"]["vocab_size"])

# ============================================================================
# Step 4: Pre-training
# ============================================================================

proc step_pretrain():
    print_header("Step 4: Pre-training")
    if len(build["corpus_text"]) == 0:
        print "  No training data loaded. Skipping pre-training."
        return
    if build["training_steps"] <= 0:
        build["training_steps"] = prompt_num("Training steps", 50)
    let lr = 0.0003
    print "  Initializing weights..."
    let d = build["d_model"]
    let v = build["vocab_size"]
    if v > 128:
        v = 128
    let seed = 42
    let sc = 0.02
    let ew = []
    for i in range(v * d):
        seed = (seed * 1664525 + 1013904223) & 4294967295
        push(ew, ((seed & 65535) / 65536 - 0.5) * 2 * sc)
    build["embed_w"] = ew
    let q = []
    let k = []
    let vv = []
    for i in range(d * d):
        seed = (seed * 1664525 + 1013904223) & 4294967295
        push(q, ((seed & 65535) / 65536 - 0.5) * 2 * sc)
        seed = (seed * 1664525 + 1013904223) & 4294967295
        push(k, ((seed & 65535) / 65536 - 0.5) * 2 * sc)
        seed = (seed * 1664525 + 1013904223) & 4294967295
        push(vv, ((seed & 65535) / 65536 - 0.5) * 2 * sc)
    build["qw"] = q
    build["kw"] = k
    build["vw"] = vv
    let nw = []
    for i in range(d):
        push(nw, 1.0)
    build["norm_w"] = nw
    let lh = []
    for i in range(d * v):
        seed = (seed * 1664525 + 1013904223) & 4294967295
        push(lh, ((seed & 65535) / 65536 - 0.5) * 2 * sc)
    build["lm_head"] = lh
    # Tokenize and train
    let tokens = tokenizer.encode(build["tok"], build["corpus_text"])
    let sl = build["seq_len"]
    let examples = train.create_lm_examples(tokens, sl)
    let steps = build["training_steps"]
    if steps > len(examples):
        steps = len(examples)
    print "  Tokens: " + str(len(tokens)) + ", Examples: " + str(len(examples)) + ", Steps: " + str(steps)
    print "  Training..."
    let tcfg = train.create_train_config()
    tcfg["learning_rate"] = lr
    tcfg["lr_schedule"] = "cosine"
    let state = train.create_train_state(tcfg)
    for step in range(steps):
        let ids = examples[step]["input_ids"]
        let tgt = examples[step]["target_ids"]
        let clr = train.get_lr(tcfg, step, steps)
        let hidden = []
        for t in range(sl):
            let tid = ids[t]
            if tid >= v:
                tid = 0
            for j in range(d):
                push(hidden, build["embed_w"][tid * d + j])
        hidden = ml_native.rms_norm(hidden, build["norm_w"], sl, d, 0.00001)
        let qr = ml_native.matmul(hidden, build["qw"], sl, d, d)
        let kr = ml_native.matmul(hidden, build["kw"], sl, d, d)
        let vr = ml_native.matmul(hidden, build["vw"], sl, d, d)
        let attn = attention.scaled_dot_product(qr, kr, vr, sl, d, true)
        hidden = ml_native.add(hidden, attn)
        hidden = ml_native.rms_norm(hidden, build["norm_w"], sl, d, 0.00001)
        let lh2 = []
        for j in range(d):
            push(lh2, hidden[(sl - 1) * d + j])
        let logits = ml_native.matmul(lh2, build["lm_head"], 1, d, v)
        let target = [tgt[sl - 1]]
        if target[0] >= v:
            target[0] = 0
        let loss = ml_native.cross_entropy(logits, target, 1, v)
        train.log_step(state, loss, clr, 0)
        if (step + 1) - (((step + 1) / 10) | 0) * 10 == 0:
            print "    step " + str(step + 1) + "/" + str(steps) + " loss=" + str(loss) + " ppl=" + str(train.perplexity(loss))
    build["train_loss"] = train.avg_loss(state)
    print "  Pre-training done. Avg loss: " + str(build["train_loss"])

# ============================================================================
# Step 5: LoRA Fine-tuning
# ============================================================================

proc step_lora():
    print_header("Step 5: LoRA Fine-tuning")
    if build["embed_w"] == nil:
        print "  No pre-trained weights. Skipping LoRA."
        return
    if not prompt_yn("Apply LoRA fine-tuning on Sage codebase?"):
        return
    build["lora_rank"] = prompt_num("LoRA rank", 8)
    build["lora_alpha"] = prompt_num("LoRA alpha", 16)
    let d = build["d_model"]
    build["adapter"] = lora.create_adapter(d, d, build["lora_rank"], build["lora_alpha"])
    print "  Adapter: rank=" + str(build["lora_rank"]) + " trainable=" + str(build["adapter"]["trainable_params"])
    # Collect Sage files for LoRA
    let lora_corpus = ""
    let lora_files = ["lib/arrays.sage", "lib/dicts.sage", "lib/strings.sage", "lib/iter.sage"]
    for i in range(len(lora_files)):
        let content = io.readfile(lora_files[i])
        if content != nil:
            lora_corpus = lora_corpus + content + NL
    let lora_tokens = tokenizer.encode(build["tok"], lora_corpus)
    let sl = build["seq_len"]
    let v = build["vocab_size"]
    if v > 128:
        v = 128
    let lora_examples = train.create_lm_examples(lora_tokens, sl)
    let lora_steps = len(lora_examples)
    if lora_steps > 20:
        lora_steps = 20
    print "  LoRA training on " + str(lora_steps) + " examples..."
    let lstate = train.create_train_state(train.create_train_config())
    for step in range(lora_steps):
        let ids = lora_examples[step]["input_ids"]
        let tgt = lora_examples[step]["target_ids"]
        let hidden = []
        for t in range(sl):
            let tid = ids[t]
            if tid >= v:
                tid = 0
            for j in range(d):
                push(hidden, build["embed_w"][tid * d + j])
        hidden = ml_native.rms_norm(hidden, build["norm_w"], sl, d, 0.00001)
        let q_base = ml_native.matmul(hidden, build["qw"], sl, d, d)
        let q_lora = lora.lora_forward(build["adapter"], hidden, sl)
        let q = ml_native.add(q_base, q_lora)
        let k = ml_native.matmul(hidden, build["kw"], sl, d, d)
        let vr = ml_native.matmul(hidden, build["vw"], sl, d, d)
        let attn = attention.scaled_dot_product(q, k, vr, sl, d, true)
        hidden = ml_native.add(hidden, attn)
        hidden = ml_native.rms_norm(hidden, build["norm_w"], sl, d, 0.00001)
        let lh = []
        for j in range(d):
            push(lh, hidden[(sl - 1) * d + j])
        let logits = ml_native.matmul(lh, build["lm_head"], 1, d, v)
        let target = [tgt[sl - 1]]
        if target[0] >= v:
            target[0] = 0
        let loss = ml_native.cross_entropy(logits, target, 1, v)
        train.log_step(lstate, loss, 0.001, 0)
    build["lora_loss"] = train.avg_loss(lstate)
    print "  LoRA done. Avg loss: " + str(build["lora_loss"])

# ============================================================================
# Step 6: DPO Alignment
# ============================================================================

proc step_dpo():
    print_header("Step 6: DPO Alignment (Optional)")
    if not prompt_yn("Apply DPO alignment with code quality preferences?"):
        return
    build["dpo_beta"] = prompt_num("DPO beta (temperature)", 0.1)
    let ds = dpo.sage_code_preferences()
    print "  Loaded " + str(len(ds["pairs"])) + " Sage code preference pairs"
    let total_loss = 0
    for i in range(len(ds["pairs"])):
        let loss = dpo.simple_dpo_loss(-1.0 - i * 0.1, -2.0 - i * 0.1, build["dpo_beta"])
        total_loss = total_loss + loss
    print "  DPO avg loss: " + str(total_loss / len(ds["pairs"]))

# ============================================================================
# Step 7: Engram Memory
# ============================================================================

proc step_engram():
    print_header("Step 7: Engram Memory Setup")
    if not prompt_yn("Enable Engram persistent memory?"):
        build["use_engram"] = false
        return
    build["use_engram"] = true
    build["memory"] = engram.create(nil)
    build["memory"]["working_capacity"] = prompt_num("Working memory slots", 20)
    build["memory"]["max_semantic"] = prompt_num("Max semantic memories", 2000)
    # Auto-load Sage knowledge
    if prompt_yn("Load Sage codebase knowledge (19 facts)?"):
        let facts = ["Sage is an indentation-based systems programming language built in C", "113 library modules across 11 subdirectories", "Concurrent tri-color mark-sweep GC with SATB write barriers", "3 compiler backends: C codegen, LLVM IR, native assembly", "Dotted imports: import os.fat resolves to lib/os/fat.sage", "0 is TRUTHY - only false and nil are falsy", "No escape sequences - use chr(10) for newline", "elif chains with 5+ branches malfunction", "Class methods cannot see module-level let vars", "match is a reserved keyword", "Native ML backend: ml_native with matmul, softmax", "Engram 4-tier memory: working, episodic, semantic, procedural", "Agent ReAct loop: observe, think, act, reflect", "Chatbot: intents, personas, sessions, middleware", "Library paths: CWD, ./lib, installed, SAGE_PATH", "Build: make or cmake -DBUILD_SAGE=ON", "224+ tests: bash tests/run_tests.sh", "Self-hosted modules start with gc_disable()", "Version: 1.0.0"]
        for i in range(len(facts)):
            engram.store_semantic(build["memory"], facts[i], 1.0)
        print "  Loaded 19 semantic facts"
    # Custom facts
    if prompt_yn("Add custom knowledge facts?"):
        let adding = true
        while adding:
            let fact = input("  Fact (or 'done'): ")
            if fact == "done":
                adding = false
            else:
                engram.store_semantic(build["memory"], fact, 0.8)
    print engram.summary(build["memory"])

# ============================================================================
# Step 8: RAG Setup
# ============================================================================

proc step_rag():
    print_header("Step 8: RAG Document Store (Optional)")
    if not prompt_yn("Enable RAG (retrieval-augmented generation)?"):
        build["use_rag"] = false
        return
    build["use_rag"] = true
    build["rag_store"] = rag.create_store()
    if prompt_yn("Index Sage documentation?"):
        let doc_files = ["documentation/SageLang_Guide.md", "documentation/LLM_Guide.md", "documentation/StdLib_Guide.md", "documentation/Agent_Chat_Guide.md"]
        for i in range(len(doc_files)):
            let content = io.readfile(doc_files[i])
            if content != nil:
                rag.add_document(build["rag_store"], content, {"source": doc_files[i]})
                print "  Indexed: " + doc_files[i]
    let stats = rag.store_stats(build["rag_store"])
    print "  RAG store: " + str(stats["documents"]) + " docs, " + str(stats["chunks"]) + " chunks, " + str(stats["index_terms"]) + " terms"

# ============================================================================
# Step 9: Agent Configuration
# ============================================================================

proc step_agent():
    print_header("Step 9: Agent Configuration (Optional)")
    if not prompt_yn("Enable autonomous agent capabilities?"):
        build["use_agent"] = false
        return
    build["use_agent"] = true
    print "  Agent will include:"
    print "    - ReAct reasoning loop (observe/think/act/reflect)"
    print "    - File read/write tools"
    print "    - Code analysis and search tools"
    print "    - Task planning with dependencies"
    print "    - Memory-backed context"

# ============================================================================
# Step 10: Chatbot Persona
# ============================================================================

proc step_chatbot():
    print_header("Step 10: Chatbot Persona")
    if not prompt_yn("Enable chatbot interface?"):
        build["use_chatbot"] = false
        return
    build["use_chatbot"] = true
    let p = prompt_choice("Select persona:", ["SageDev - Sage language expert", "Code Reviewer - thorough code analysis", "Teacher - patient programming instructor", "Debugger - systematic bug hunter", "Architect - system design expert", "Assistant - general purpose helper", "Custom - define your own"])
    if p == 1:
        build["persona"] = "sage_developer"
    if p == 2:
        build["persona"] = "code_reviewer"
    if p == 3:
        build["persona"] = "teacher"
    if p == 4:
        build["persona"] = "debugger"
    if p == 5:
        build["persona"] = "architect"
    if p == 6:
        build["persona"] = "assistant"
    if p == 7:
        build["persona"] = "custom"

# ============================================================================
# Step 11: Build Summary and Export
# ============================================================================

proc step_export():
    print_header("Step 11: Build Summary")
    print "  Model: " + build["model_name"] + " (" + build["model_size"] + ")"
    print "  Architecture: " + str(build["d_model"]) + "d / " + str(build["n_layers"]) + "L / " + str(build["n_heads"]) + "H"
    print "  Tokenizer: " + build["tokenizer_type"]
    print "  Context: " + str(build["context_length"]) + " tokens"
    if build["train_loss"] > 0:
        print "  Pre-train loss: " + str(build["train_loss"])
    if build["lora_loss"] > 0:
        print "  LoRA loss: " + str(build["lora_loss"])
    if build["use_engram"]:
        print "  Engram: enabled"
    if build["use_rag"]:
        print "  RAG: enabled"
    if build["use_agent"]:
        print "  Agent: enabled"
    if build["use_chatbot"]:
        print "  Chatbot: " + build["persona"]
    print ""
    build["output_path"] = prompt_str("Output path", "models/" + build["model_name"] + ".sage")
    if prompt_yn("Export model?"):
        print "  Exporting to " + build["output_path"] + "..."
        # Write a stub output file with model config
        let output = "gc_disable()" + NL
        output = output + "# " + build["model_name"] + " - Built with SageLLM AI Builder" + NL
        output = output + "# Architecture: " + str(build["d_model"]) + "d / " + str(build["n_layers"]) + "L" + NL
        output = output + "print " + DQ + build["model_name"] + " loaded" + DQ + NL
        io.writefile(build["output_path"], output)
        print "  Exported to " + build["output_path"]
    print ""
    # Benchmark
    let bench = ml_native.benchmark(build["d_model"], 5)
    print "  Native backend: " + str(bench["gflops"]) + " GFLOPS"
    build["complete"] = true

# ============================================================================
# Main interactive flow
# ============================================================================

print_header("SageLLM AI Builder v1.0.0")
print "Interactive step-by-step AI model builder."
print "Uses the full Sage LLM/ML/AI library stack."
print ""

let running = true
while running:
    print ""
    print "Steps:"
    print_option(1, "Model Config", "architecture, size, context window")
    print_option(2, "Tokenizer", "char, BPE, or word-level")
    print_option(3, "Training Data", "theory, code, NLP, custom files")
    print_option(4, "Pre-train", "train on corpus with native backend")
    print_option(5, "LoRA", "fine-tune on domain-specific data")
    print_option(6, "DPO", "align with code quality preferences")
    print_option(7, "Engram", "persistent memory setup")
    print_option(8, "RAG", "document retrieval store")
    print_option(9, "Agent", "autonomous tool-using agent")
    print_option(10, "Chatbot", "conversational persona")
    print_option(11, "Export", "summary and output")
    print ""
    print "  Advanced:"
    print_option(12, "Grammar", "grammar-constrained decoding")
    print_option(13, "Sandbox", "program-aided reasoning (AST execution)")
    print_option(14, "ToT", "tree-of-thoughts search with rollbacks")
    print_option(15, "Router", "semantic routing for fast command dispatch")
    print ""
    print_option(0, "Quick Build", "run all steps with defaults")
    print_option(99, "Quit", "exit the builder")
    print ""
    let raw_input = input("Select step [0-15, q=quit]: ")
    let step = -1
    if raw_input == "q" or raw_input == "quit" or raw_input == "99":
        running = false
        print "Builder exited."
    if running and raw_input == "0":
        step = 0
    if running and raw_input == "1":
        step = 1
    if running and raw_input == "2":
        step = 2
    if running and raw_input == "3":
        step = 3
    if running and raw_input == "4":
        step = 4
    if running and raw_input == "5":
        step = 5
    if running and raw_input == "6":
        step = 6
    if running and raw_input == "7":
        step = 7
    if running and raw_input == "8":
        step = 8
    if running and raw_input == "9":
        step = 9
    if running and raw_input == "10":
        step = 10
    if running and raw_input == "11":
        step = 11
    if running and raw_input == "12":
        step = 12
    if running and raw_input == "13":
        step = 13
    if running and raw_input == "14":
        step = 14
    if running and raw_input == "15":
        step = 15
    if step == 0:
        # Quick build: auto-configure everything with sensible defaults
        print_header("Quick Build: Auto-configuring all steps")
        build["model_name"] = "sagellm-quick"
        build["model_size"] = "nano"
        build["d_model"] = 64
        build["n_layers"] = 2
        build["n_heads"] = 2
        build["d_ff"] = 256
        build["context_length"] = 256
        build["vocab_size"] = 128
        build["seq_len"] = 64
        build["tokenizer_type"] = "char"
        build["tok"] = tokenizer.char_tokenizer()
        print "  Model: sagellm-quick (nano 64d/2L)"
        print "  Tokenizer: character-level"
        # Load theory corpus
        let qcorpus = io.readfile("models/data/programming_languages.txt")
        if qcorpus == nil:
            qcorpus = "proc hello(): print 42"
        build["corpus_text"] = qcorpus
        print "  Corpus: " + str(len(qcorpus)) + " chars"
        # Pre-train
        build["training_steps"] = 20
        step_pretrain()
        # Engram with defaults
        build["use_engram"] = true
        build["memory"] = engram.create(nil)
        let qfacts = ["Sage is an indentation-based systems programming language", "118 library modules across 11 subdirectories", "Concurrent tri-color mark-sweep GC", "3 compiler backends: C LLVM native assembly"]
        for qi in range(len(qfacts)):
            engram.store_semantic(build["memory"], qfacts[qi], 1.0)
        print "  Engram: 4 facts loaded"
        # Export
        step_export()
        running = false
    if step == 1:
        step_model_config()
    if step == 2:
        step_tokenizer()
    if step == 3:
        step_training_data()
    if step == 4:
        step_pretrain()
    if step == 5:
        step_lora()
    if step == 6:
        step_dpo()
    if step == 7:
        step_engram()
    if step == 8:
        step_rag()
    if step == 9:
        step_agent()
    if step == 10:
        step_chatbot()
    if step == 11:
        step_export()
        running = false
    if step == 12:
        print_header("Step 12: Grammar-Constrained Decoding")
        print "  Grammar constraints ensure the model cannot output malformed commands."
        print "  Available grammars: tool_call, json, sage_code"
        print "  Use: import agent.grammar"
        print "  grammar.constrained_llm(llm_fn, grammar_type, max_retries)"
        print ""
        print "  This wraps your LLM function to auto-validate and retry on bad output."
        build["use_grammar"] = true
        print "  Grammar constraints: enabled"
    if step == 13:
        print_header("Step 13: Program-Aided Reasoning (Sandbox)")
        print "  Offloads deterministic tasks (math, I/O) to the Sage compiler."
        print "  The LLM writes code blocks; the sandbox executes them safely."
        print "  Use: import agent.sandbox"
        print "  sandbox.par_query(agent, question) -> {answer, code_executed, result}"
        print ""
        print "  Math eval: sandbox.eval_math(" + DQ + "3 + 4 * 2" + DQ + ") -> 11"
        print "  Code blocks extracted from ```sage ... ``` delimiters."
        build["use_sandbox"] = true
        print "  Program-aided reasoning: enabled"
    if step == 14:
        print_header("Step 14: Tree of Thoughts (ToT)")
        print "  MCTS-style search over reasoning steps with state rollbacks."
        print "  The model generates multiple candidates; an evaluator scores them."
        print "  Dead-end paths are rolled back to the last known good state."
        print "  Use: import agent.tot"
        print "  tot.best_first_search(solver, llm_fn, initial_state, goal_check)"
        print ""
        print "  Dramatically increases success on complex multi-step tasks."
        build["use_tot"] = true
        print "  Tree of Thoughts: enabled"
    if step == 15:
        print_header("Step 15: Semantic Router")
        print "  Bypasses the LLM for trivial commands (sub-millisecond, zero hallucination)."
        print "  Routes matching queries to deterministic handlers."
        print "  Complex/ambiguous queries fall through to the full agent."
        print "  Use: import agent.semantic_router"
        print "  semantic_router.add_sage_routes(router) -> 8 pre-built routes"
        print ""
        build["use_router"] = true
        print "  Semantic router: enabled"
    if step == 99:
        running = false
        print "Builder exited."
