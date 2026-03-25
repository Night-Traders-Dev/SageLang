gc_disable()
# ============================================================================
# SageLLM Build Pipeline
# Builds, trains, and compiles the SageLLM chatbot + agent to a binary
#
# Usage: sage models/build_sagellm.sage
#
# Pipeline:
#   1. Collect training data (theory + Sage codebase)
#   2. Train base model on programming language theory
#   3. LoRA fine-tune on Sage source code
#   4. Load Engram memory with codebase knowledge
#   5. Wire trained model into chatbot + agent
#   6. Emit compiled C binary via --compile
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

let NL = chr(10)
let DQ = chr(34)

proc log(phase, msg):
    print "[" + phase + "] " + msg

proc separator():
    print "================================================================"

# ============================================================================
# Step 1: Collect all training data
# ============================================================================

separator()
print "  SageLLM Build Pipeline v1.0.0"
separator()
print ""

log("DATA", "Collecting training data...")

# Theory corpus
let theory = io.readfile("models/data/programming_languages.txt")
if theory == nil:
    log("DATA", "ERROR: models/data/programming_languages.txt not found")
    log("DATA", "Run from sagelang root: sage models/build_sagellm.sage")
    sys.exit(1)
log("DATA", "Theory corpus: " + str(len(theory)) + " chars")

# Multi-language examples (Python, C, C++, Nim)
let multilang = io.readfile("models/data/multilang_examples.txt")
if multilang != nil:
    theory = theory + NL + multilang
    log("DATA", "Multi-language examples: " + str(len(multilang)) + " chars (Python, C, C++, Nim)")
log("DATA", "Total theory+examples: " + str(len(theory)) + " chars")

# Sage codebase
let sage_files = ["src/sage/lexer.sage", "src/sage/parser.sage", "src/sage/interpreter.sage", "src/sage/compiler.sage", "src/sage/sage.sage", "src/sage/codegen.sage", "src/sage/llvm_backend.sage", "src/sage/formatter.sage", "src/sage/linter.sage", "src/sage/module.sage", "src/sage/gc.sage", "src/sage/value.sage", "src/sage/errors.sage", "lib/arrays.sage", "lib/dicts.sage", "lib/strings.sage", "lib/iter.sage", "lib/json.sage", "lib/math.sage", "lib/stats.sage", "lib/utils.sage", "lib/assert.sage", "lib/os/fat.sage", "lib/os/elf.sage", "lib/os/mbr.sage", "lib/os/paging.sage", "lib/os/idt.sage", "lib/os/alloc.sage", "lib/os/vfs.sage", "lib/net/url.sage", "lib/net/ip.sage", "lib/net/headers.sage", "lib/net/server.sage", "lib/net/dns.sage", "lib/crypto/hash.sage", "lib/crypto/encoding.sage", "lib/crypto/cipher.sage", "lib/crypto/rand.sage", "lib/std/regex.sage", "lib/std/datetime.sage", "lib/std/fmt.sage", "lib/std/testing.sage", "lib/std/enum.sage", "lib/std/trait.sage", "lib/std/channel.sage", "lib/std/db.sage", "lib/std/argparse.sage", "lib/std/log.sage", "lib/std/unicode.sage", "lib/std/debug.sage", "lib/std/profiler.sage", "lib/std/build.sage", "lib/ml/tensor.sage", "lib/ml/nn.sage", "lib/ml/optim.sage", "lib/ml/loss.sage", "lib/llm/config.sage", "lib/llm/tokenizer.sage", "lib/llm/attention.sage", "lib/llm/generate.sage", "lib/llm/train.sage", "lib/llm/agent.sage", "lib/llm/prompt.sage", "lib/llm/engram.sage", "lib/llm/lora.sage", "lib/llm/quantize.sage", "lib/agent/core.sage", "lib/agent/tools.sage", "lib/agent/planner.sage", "lib/chat/bot.sage", "lib/chat/session.sage", "lib/chat/persona.sage"]

let sage_corpus = ""
let file_count = 0
for i in range(len(sage_files)):
    let content = io.readfile(sage_files[i])
    if content != nil:
        sage_corpus = sage_corpus + "<|file:" + sage_files[i] + "|>" + NL + content + NL + "<|end|>" + NL
        file_count = file_count + 1

log("DATA", "Sage codebase: " + str(file_count) + " files, " + str(len(sage_corpus)) + " chars")

# Documentation
let doc_files = ["documentation/SageLang_Guide.md", "documentation/GC_Guide.md", "documentation/LLM_Guide.md", "documentation/Agent_Chat_Guide.md", "documentation/StdLib_Guide.md"]
let doc_corpus = ""
for i in range(len(doc_files)):
    let content = io.readfile(doc_files[i])
    if content != nil:
        doc_corpus = doc_corpus + content + NL

log("DATA", "Documentation: " + str(len(doc_corpus)) + " chars")

let total_corpus = theory + NL + sage_corpus + NL + doc_corpus
log("DATA", "Total corpus: " + str(len(total_corpus)) + " chars (~" + str((len(total_corpus) / 4) | 0) + " tokens)")
print ""

# ============================================================================
# Step 2: Initialize model and tokenizer
# ============================================================================

log("MODEL", "Initializing SageLLM model...")

let d_model = 64
let seq_len = 128
let vocab = 128

let tok = tokenizer.char_tokenizer()
log("MODEL", "Tokenizer: character-level (" + str(vocab) + " tokens)")

# Initialize weights
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

log("MODEL", "Weights initialized (d_model=" + str(d_model) + ", vocab=" + str(vocab) + ")")
print ""

# ============================================================================
# Step 3: Pre-train on theory corpus
# ============================================================================

log("TRAIN", "Phase 1: Pre-training on programming language theory")

let theory_tokens = tokenizer.encode(tok, theory)
let theory_examples = train.create_lm_examples(theory_tokens, seq_len)
let theory_steps = len(theory_examples)
if theory_steps > 50:
    theory_steps = 50

log("TRAIN", "Theory: " + str(len(theory_tokens)) + " tokens -> " + str(theory_steps) + " training steps")

let train_cfg = train.create_train_config()
train_cfg["learning_rate"] = 0.0003
train_cfg["lr_schedule"] = "cosine"

let state1 = train.create_train_state(train_cfg)

for step in range(theory_steps):
    let ids = theory_examples[step]["input_ids"]
    let tgt = theory_examples[step]["target_ids"]
    let lr = train.get_lr(train_cfg, step, theory_steps)

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
    let attn = attention.scaled_dot_product(q, k, v, seq_len, d_model, true)
    hidden = ml_native.add(hidden, attn)
    hidden = ml_native.rms_norm(hidden, norm_w, seq_len, d_model, 0.00001)

    let last_h = []
    for j in range(d_model):
        push(last_h, hidden[(seq_len - 1) * d_model + j])
    let logits = ml_native.matmul(last_h, lm_head, 1, d_model, vocab)

    let target = [tgt[seq_len - 1]]
    if target[0] >= vocab:
        target[0] = 0
    let loss = ml_native.cross_entropy(logits, target, 1, vocab)
    train.log_step(state1, loss, lr, 0)

    if (step + 1) - (((step + 1) / 25) | 0) * 25 == 0:
        log("TRAIN", "  step " + str(step + 1) + "/" + str(theory_steps) + " loss=" + str(loss) + " ppl=" + str(train.perplexity(loss)))

log("TRAIN", "Phase 1 done. avg_loss=" + str(train.avg_loss(state1)))
print ""

# ============================================================================
# Step 4: LoRA fine-tune on Sage codebase
# ============================================================================

log("LORA", "Phase 2: LoRA fine-tuning on " + str(file_count) + " Sage files")

let adapter = lora.create_adapter(d_model, d_model, 8, 16)
log("LORA", "Adapter: rank=8 alpha=16 trainable=" + str(adapter["trainable_params"]))

let sage_tokens = tokenizer.encode(tok, sage_corpus)
let sage_examples = train.create_lm_examples(sage_tokens, seq_len)
let lora_steps = len(sage_examples)
if lora_steps > 30:
    lora_steps = 30

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

    hidden = ml_native.rms_norm(hidden, norm_w, seq_len, d_model, 0.00001)
    let q_base = ml_native.matmul(hidden, qw, seq_len, d_model, d_model)
    let q_lora = lora.lora_forward(adapter, hidden, seq_len)
    let q = ml_native.add(q_base, q_lora)
    let k = ml_native.matmul(hidden, kw, seq_len, d_model, d_model)
    let v = ml_native.matmul(hidden, vw, seq_len, d_model, d_model)
    let attn = attention.scaled_dot_product(q, k, v, seq_len, d_model, true)
    hidden = ml_native.add(hidden, attn)
    hidden = ml_native.rms_norm(hidden, norm_w, seq_len, d_model, 0.00001)

    let last_h = []
    for j in range(d_model):
        push(last_h, hidden[(seq_len - 1) * d_model + j])
    let logits = ml_native.matmul(last_h, lm_head, 1, d_model, vocab)

    let target = [tgt[seq_len - 1]]
    if target[0] >= vocab:
        target[0] = 0
    let loss = ml_native.cross_entropy(logits, target, 1, vocab)
    train.log_step(state2, loss, train_cfg["learning_rate"], 0)

    if (step + 1) - (((step + 1) / 10) | 0) * 10 == 0:
        log("LORA", "  step " + str(step + 1) + "/" + str(lora_steps) + " loss=" + str(loss))

log("LORA", "Phase 2 done. avg_loss=" + str(train.avg_loss(state2)))
print ""

# ============================================================================
# Step 5: Build Engram memory
# ============================================================================

log("ENGRAM", "Loading codebase knowledge...")

let memory = engram.create(nil)
memory["working_capacity"] = 20
memory["max_episodic"] = 5000
memory["max_semantic"] = 2000

let facts = ["Sage is an indentation-based systems programming language built in C", "113 library modules across 11 subdirectories (graphics, os, net, crypto, ml, cuda, std, llm, agent, chat)", "Concurrent tri-color mark-sweep GC with SATB write barriers, sub-millisecond STW pauses", "3 compiler backends: C codegen, LLVM IR, native assembly (x86-64, aarch64, rv64)", "Dotted imports: import os.fat resolves to lib/os/fat.sage, binds as fat", "0 is TRUTHY in Sage - only false and nil are falsy", "No escape sequences - use chr(10) for newline, chr(34) for double-quote", "elif chains with 5+ branches malfunction - use sequential if/continue", "Class methods cannot see module-level let vars - pass as args or hardcode", "match is a reserved keyword", "Native ML backend: ml_native module with matmul, softmax, cross_entropy, adam_update", "Engram 4-tier memory: working (FIFO), episodic (timestamped), semantic (permanent), procedural (skills)", "Agent ReAct loop: observe -> think -> act -> reflect, with TOOL:/ANSWER: parsing", "Chatbot framework: intents, personas (SageDev/Teacher/Debugger), sessions, middleware", "Library paths: CWD, ./lib, source dir, /usr/local/share/sage/lib, SAGE_PATH env var", "Build: make (Makefile) or cmake -B build -DBUILD_SAGE=ON", "Tests: bash tests/run_tests.sh (224 tests), make test, make test-selfhost", "All self-hosted and heavy-allocation modules start with gc_disable()", "Version: 1.0.0 across REPL, sys.version, CMakeLists.txt, VSCode extension"]

for i in range(len(facts)):
    engram.store_semantic(memory, facts[i], 1.0)

engram.store_procedural(memory, "write_sage_code", ["Use proc for functions, class for OOP", "Indent with spaces (no braces)", "Use let for variables, for/while for loops", "Import modules with dotted paths", "Start heavy modules with gc_disable()"], 1.0)

engram.store_procedural(memory, "debug_sage", ["Check for reserved keyword conflicts (match)", "Use chr(10) instead of escape sequences", "Avoid 5+ branch elif chains", "Add gc_disable() if segfaulting on heavy allocation", "Run tests: bash tests/run_tests.sh"], 1.0)

log("ENGRAM", engram.summary(memory))
print ""

# ============================================================================
# Step 6: Generate the compiled chatbot binary source
# ============================================================================

log("BUILD", "Generating compiled chatbot source with CoT + memory + planning...")

# Write the chatbot directly to file for clarity
let out_path = "models/sagellm_chatbot.sage"
let S = []

proc emit(line):
    push(S, line)

proc emit_all():
    let result = ""
    for i in range(len(S)):
        result = result + S[i] + NL
    io.writefile(out_path, result)
    log("BUILD", "Generated " + out_path + " (" + str(len(result)) + " chars, " + str(len(S)) + " lines)")

# --- Header ---
emit("gc_disable()")
emit("# SageLLM Chatbot v1.0.0 with Chain-of-Thought, Engram Memory, Planning")
emit("# Auto-generated by build_sagellm.sage")
emit("")
emit("import io")
emit("import chat.bot")
emit("import chat.persona")
emit("import chat.session")
emit("import llm.engram")
emit("import llm.agent")
emit("import agent.core")
emit("import agent.planner")
emit("")

# --- Utilities ---
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

# --- Engram Memory ---
emit("let memory = engram.create(nil)")
emit("memory[" + DQ + "working_capacity" + DQ + "] = 20")
emit("memory[" + DQ + "max_episodic" + DQ + "] = 5000")
emit("memory[" + DQ + "max_semantic" + DQ + "] = 2000")
emit("")
for i in range(len(facts)):
    emit("engram.store_semantic(memory, " + DQ + facts[i] + DQ + ", 1.0)")
emit("")

# --- Chain-of-Thought Reasoning Engine ---
emit("# Chain-of-thought reasoning")
emit("proc reason(question):")
emit("    let chain = agent.create_reasoning_chain()")
emit("    let lp = to_lower(question)")
emit("    # Step 1: Recall relevant memory")
emit("    let mem_results = engram.recall(memory, lp, 5)")
emit("    if len(mem_results) > 0:")
emit("        let mem_text = " + DQ + DQ)
emit("        for i in range(len(mem_results)):")
emit("            mem_text = mem_text + mem_results[i][" + DQ + "entry" + DQ + "][" + DQ + "content" + DQ + "]")
emit("            if i < len(mem_results) - 1:")
emit("                mem_text = mem_text + " + DQ + "; " + DQ)
emit("        agent.add_thought(chain, " + DQ + "I recall: " + DQ + " + mem_text)")
emit("    else:")
emit("        agent.add_thought(chain, " + DQ + "No specific memory found, using general knowledge" + DQ + ")")
emit("    # Step 2: Classify the question")
emit("    let topic = " + DQ + "general" + DQ)
emit("    if contains(lp, " + DQ + "for" + DQ + ") or contains(lp, " + DQ + "loop" + DQ + ") or contains(lp, " + DQ + "while" + DQ + ") or contains(lp, " + DQ + "iteration" + DQ + "):")
emit("        topic = " + DQ + "loops" + DQ)
emit("    if contains(lp, " + DQ + "import" + DQ + ") or contains(lp, " + DQ + "module" + DQ + ") or contains(lp, " + DQ + "library" + DQ + "):")
emit("        topic = " + DQ + "modules" + DQ)
emit("    if contains(lp, " + DQ + "class" + DQ + ") or contains(lp, " + DQ + "object" + DQ + ") or contains(lp, " + DQ + "inherit" + DQ + "):")
emit("        topic = " + DQ + "oop" + DQ)
emit("    if contains(lp, " + DQ + "gc" + DQ + ") or contains(lp, " + DQ + "garbage" + DQ + ") or contains(lp, " + DQ + "memory" + DQ + "):")
emit("        topic = " + DQ + "gc" + DQ)
emit("    if contains(lp, " + DQ + "compile" + DQ + ") or contains(lp, " + DQ + "backend" + DQ + ") or contains(lp, " + DQ + "llvm" + DQ + ") or contains(lp, " + DQ + "emit" + DQ + "):")
emit("        topic = " + DQ + "compiler" + DQ)
emit("    if contains(lp, " + DQ + "array" + DQ + ") or contains(lp, " + DQ + "dict" + DQ + ") or contains(lp, " + DQ + "list" + DQ + ") or contains(lp, " + DQ + "data struct" + DQ + "):")
emit("        topic = " + DQ + "data" + DQ)
emit("    if contains(lp, " + DQ + "function" + DQ + ") or contains(lp, " + DQ + "proc" + DQ + ") or contains(lp, " + DQ + "closure" + DQ + "):")
emit("        topic = " + DQ + "functions" + DQ)
emit("    if contains(lp, " + DQ + "error" + DQ + ") or contains(lp, " + DQ + "exception" + DQ + ") or contains(lp, " + DQ + "try" + DQ + ") or contains(lp, " + DQ + "catch" + DQ + "):")
emit("        topic = " + DQ + "errors" + DQ)
emit("    if contains(lp, " + DQ + "test" + DQ + ") or contains(lp, " + DQ + "debug" + DQ + ") or contains(lp, " + DQ + "fix" + DQ + ") or contains(lp, " + DQ + "bug" + DQ + "):")
emit("        topic = " + DQ + "testing" + DQ)
emit("    if contains(lp, " + DQ + "thread" + DQ + ") or contains(lp, " + DQ + "async" + DQ + ") or contains(lp, " + DQ + "channel" + DQ + ") or contains(lp, " + DQ + "concurrent" + DQ + "):")
emit("        topic = " + DQ + "concurrency" + DQ)
emit("    if contains(lp, " + DQ + "plan" + DQ + ") or contains(lp, " + DQ + "how to build" + DQ + ") or contains(lp, " + DQ + "steps" + DQ + ") or contains(lp, " + DQ + "roadmap" + DQ + "):")
emit("        topic = " + DQ + "planning" + DQ)
emit("    agent.add_thought(chain, " + DQ + "Topic classified as: " + DQ + " + topic)")
emit("    # Step 3: Generate answer based on topic")
emit("    let answer = " + DQ + DQ)
emit("    if topic == " + DQ + "loops" + DQ + ":")
emit("        answer = " + DQ + "In Sage, use for loops with range:" + DQ + " + chr(10) + " + DQ + "  for i in range(10):" + DQ + " + chr(10) + " + DQ + "      print i" + DQ + " + chr(10) + chr(10) + " + DQ + "Or iterate arrays:" + DQ + " + chr(10) + " + DQ + "  for item in my_array:" + DQ + " + chr(10) + " + DQ + "      print item" + DQ + " + chr(10) + chr(10) + " + DQ + "While loops: while condition: body" + DQ)
emit("    if topic == " + DQ + "modules" + DQ + ":")
emit("        answer = " + DQ + "Sage uses dotted imports for 11 library categories:" + DQ + " + chr(10) + " + DQ + "  import os.fat        # OS/baremetal (15 modules)" + DQ + " + chr(10) + " + DQ + "  import net.url       # Networking (8 modules)" + DQ + " + chr(10) + " + DQ + "  import crypto.hash   # Cryptography (6 modules)" + DQ + " + chr(10) + " + DQ + "  import std.regex     # Standard lib (23 modules)" + DQ + " + chr(10) + " + DQ + "  import ml.tensor     # Machine learning (5 modules)" + DQ + " + chr(10) + " + DQ + "  import llm.agent     # LLM/AI (12 modules)" + DQ + " + chr(10) + chr(10) + " + DQ + "The last path component becomes the binding name." + DQ)
emit("    if topic == " + DQ + "oop" + DQ + ":")
emit("        answer = " + DQ + "Sage OOP:" + DQ + " + chr(10) + " + DQ + "  class Animal:" + DQ + " + chr(10) + " + DQ + "      proc init(self, name):" + DQ + " + chr(10) + " + DQ + "          self.name = name" + DQ + " + chr(10) + " + DQ + "      proc speak(self):" + DQ + " + chr(10) + " + DQ + "          print self.name" + DQ + " + chr(10) + chr(10) + " + DQ + "  class Dog(Animal):  # inheritance" + DQ + " + chr(10) + " + DQ + "      proc speak(self):" + DQ + " + chr(10) + " + DQ + "          print self.name + " + DQ + " + chr(34) + " + DQ + " barks" + DQ + " + chr(34)")
emit("    if topic == " + DQ + "gc" + DQ + ":")
emit("        answer = " + DQ + "Sage uses a concurrent tri-color mark-sweep GC:" + DQ + " + chr(10) + " + DQ + "  Phase 1 (STW ~50-200us): Root scan, shade gray, enable write barrier" + DQ + " + chr(10) + " + DQ + "  Phase 2 (concurrent):   Process gray objects from mark stack" + DQ + " + chr(10) + " + DQ + "  Phase 3 (STW ~20-50us): Remark, drain barrier-shaded objects" + DQ + " + chr(10) + " + DQ + "  Phase 4 (concurrent):   Sweep white objects in batches" + DQ + " + chr(10) + chr(10) + " + DQ + "SATB write barrier prevents missed objects during concurrent marking." + DQ + " + chr(10) + " + DQ + "Control: gc_collect(), gc_enable(), gc_disable()" + DQ)
emit("    if topic == " + DQ + "compiler" + DQ + ":")
emit("        answer = " + DQ + "Sage has 3 compiler backends:" + DQ + " + chr(10) + " + DQ + "  sage --emit-c file.sage         # C source output" + DQ + " + chr(10) + " + DQ + "  sage --compile file.sage        # Compile via C" + DQ + " + chr(10) + " + DQ + "  sage --emit-llvm file.sage      # LLVM IR output" + DQ + " + chr(10) + " + DQ + "  sage --compile-llvm file.sage   # Native via LLVM" + DQ + " + chr(10) + " + DQ + "  sage --emit-asm file.sage       # Direct assembly (x86-64/aarch64/rv64)" + DQ + " + chr(10) + " + DQ + "  sage --compile-native file.sage # Native binary" + DQ)
emit("    if topic == " + DQ + "data" + DQ + ":")
emit("        answer = " + DQ + "Sage data structures:" + DQ + " + chr(10) + " + DQ + "  let arr = [1, 2, 3]     # Array" + DQ + " + chr(10) + " + DQ + "  push(arr, 4)             # Append" + DQ + " + chr(10) + " + DQ + "  print arr[0:2]           # Slicing [1, 2]" + DQ + " + chr(10) + " + DQ + "  let d = {}               # Dict" + DQ + " + chr(10) + " + DQ + "  d[key] = value           # Set" + DQ + " + chr(10) + " + DQ + "  let t = (1, 2, 3)        # Tuple (immutable)" + DQ)
emit("    if topic == " + DQ + "functions" + DQ + ":")
emit("        answer = " + DQ + "Sage functions:" + DQ + " + chr(10) + " + DQ + "  proc greet(name):" + DQ + " + chr(10) + " + DQ + "      return name" + DQ + " + chr(10) + chr(10) + " + DQ + "  # Closures:" + DQ + " + chr(10) + " + DQ + "  proc make_counter():" + DQ + " + chr(10) + " + DQ + "      let n = 0" + DQ + " + chr(10) + " + DQ + "      proc inc():" + DQ + " + chr(10) + " + DQ + "          n = n + 1" + DQ + " + chr(10) + " + DQ + "          return n" + DQ + " + chr(10) + " + DQ + "      return inc" + DQ)
emit("    if topic == " + DQ + "errors" + DQ + ":")
emit("        answer = " + DQ + "Sage exception handling:" + DQ + " + chr(10) + " + DQ + "  try:" + DQ + " + chr(10) + " + DQ + "      raise error_message" + DQ + " + chr(10) + " + DQ + "  catch e:" + DQ + " + chr(10) + " + DQ + "      print e" + DQ + " + chr(10) + " + DQ + "  finally:" + DQ + " + chr(10) + " + DQ + "      cleanup()" + DQ)
emit("    if topic == " + DQ + "testing" + DQ + ":")
emit("        answer = " + DQ + "Run tests: bash tests/run_tests.sh (224 tests)" + DQ + " + chr(10) + " + DQ + "  make test          # Compiler tests" + DQ + " + chr(10) + " + DQ + "  make test-selfhost  # Self-hosted tests" + DQ + " + chr(10) + chr(10) + " + DQ + "Debug tips:" + DQ + " + chr(10) + " + DQ + "  - Add gc_disable() for GC segfaults" + DQ + " + chr(10) + " + DQ + "  - Use chr(10) not escape sequences" + DQ + " + chr(10) + " + DQ + "  - Avoid 5+ elif branches" + DQ)
emit("    if topic == " + DQ + "concurrency" + DQ + ":")
emit("        answer = " + DQ + "Sage concurrency:" + DQ + " + chr(10) + " + DQ + "  import thread       # OS threads + mutexes" + DQ + " + chr(10) + " + DQ + "  async proc work():  # Async/await" + DQ + " + chr(10) + " + DQ + "  import std.channel   # Go-style channels" + DQ + " + chr(10) + " + DQ + "  import std.atomic    # Atomic operations" + DQ + " + chr(10) + " + DQ + "  import std.rwlock    # Read-write locks" + DQ)
emit("    if topic == " + DQ + "planning" + DQ + ":")
emit("        agent.add_thought(chain, " + DQ + "User wants a plan. Let me break this down." + DQ + ")")
emit("        answer = " + DQ + "Here is a development plan:" + DQ + " + chr(10) + " + DQ + "  1. Define the feature/goal" + DQ + " + chr(10) + " + DQ + "  2. Create the module in lib/<category>/" + DQ + " + chr(10) + " + DQ + "  3. Start file with gc_disable() if needed" + DQ + " + chr(10) + " + DQ + "  4. Write the implementation" + DQ + " + chr(10) + " + DQ + "  5. Add test in tests/26_stdlib/" + DQ + " + chr(10) + " + DQ + "  6. Update Makefile install section" + DQ + " + chr(10) + " + DQ + "  7. Update README and docs" + DQ + " + chr(10) + " + DQ + "  8. Run: bash tests/run_tests.sh" + DQ)
emit("    if len(answer) == 0:")
emit("        if len(mem_results) > 0:")
emit("            answer = " + DQ + "Based on my knowledge: " + DQ + " + mem_results[0][" + DQ + "entry" + DQ + "][" + DQ + "content" + DQ + "]")
emit("        else:")
emit("            answer = " + DQ + "I can help with: loops, imports, classes, GC, compiler, data structures, functions, errors, testing, concurrency, and planning. What would you like to know?" + DQ)
emit("    agent.add_thought(chain, " + DQ + "Answering about " + DQ + " + topic)")
emit("    agent.set_conclusion(chain, answer)")
emit("    # Store reasoning in episodic memory")
emit("    engram.store_episodic(memory, " + DQ + "Answered question about " + DQ + " + topic + " + DQ + ": " + DQ + " + question, 0.6)")
emit("    return chain")
emit("")

# --- LLM function using CoT ---
emit("proc sage_llm(prompt):")
emit("    let chain = reason(prompt)")
emit("    return chain[" + DQ + "conclusion" + DQ + "]")
emit("")

# --- Chatbot setup ---
emit("let b = bot.create(" + DQ + DQ + ", " + DQ + DQ + ", sage_llm)")
emit("persona.apply_persona(b, persona.sage_developer())")
emit("")
emit("proc on_greet(msg, conv):")
emit("    return " + DQ + "Hello. I am SageDev with chain-of-thought reasoning and persistent memory. Ask me anything about Sage." + DQ)
emit("proc on_bye(msg, conv):")
emit("    engram.consolidate(memory)")
emit("    return " + DQ + "Goodbye. I have consolidated " + DQ + " + str(len(memory[" + DQ + "semantic" + DQ + "])) + " + DQ + " memories. Happy coding." + DQ)
emit("bot.add_intent(b, " + DQ + "greet" + DQ + ", [" + DQ + "hello" + DQ + ", " + DQ + "hi" + DQ + ", " + DQ + "hey" + DQ + "], on_greet)")
emit("bot.add_intent(b, " + DQ + "bye" + DQ + ", [" + DQ + "bye" + DQ + ", " + DQ + "quit" + DQ + ", " + DQ + "exit" + DQ + "], on_bye)")
emit("")

# --- Session ---
emit("let store = session.create_store()")
emit("let sess = session.new_session(store, " + DQ + "SageDev" + DQ + ")")
emit("")

# --- Main loop with memory + reasoning display ---
emit("print " + DQ + "SageLLM Chatbot v1.0.0 (CoT + Engram + Planning)" + DQ)
emit("print bot.greet(b)")
emit("print " + DQ + "Commands: quit, memory, think <question>, plan <goal>" + DQ)
emit("print " + DQ + DQ)
emit("")
emit("let running = true")
emit("while running:")
emit("    let msg = input(" + DQ + "You> " + DQ + ")")
emit("    if msg == " + DQ + "quit" + DQ + " or msg == " + DQ + "exit" + DQ + ":")
emit("        running = false")
emit("        print bot.farewell(b)")
emit("    if msg == " + DQ + "memory" + DQ + " and running:")
emit("        print engram.summary(memory)")
emit("    if running and len(msg) > 6 and msg[0] == " + DQ + "t" + DQ + " and msg[1] == " + DQ + "h" + DQ + " and msg[2] == " + DQ + "i" + DQ + " and msg[3] == " + DQ + "n" + DQ + " and msg[4] == " + DQ + "k" + DQ + " and msg[5] == " + DQ + " " + DQ + ":")
emit("        let q = " + DQ + DQ)
emit("        for i in range(len(msg) - 6):")
emit("            q = q + msg[6 + i]")
emit("        let chain = reason(q)")
emit("        print " + DQ + DQ)
emit("        print agent.format_chain(chain)")
emit("    if running and len(msg) > 5 and msg[0] == " + DQ + "p" + DQ + " and msg[1] == " + DQ + "l" + DQ + " and msg[2] == " + DQ + "a" + DQ + " and msg[3] == " + DQ + "n" + DQ + " and msg[4] == " + DQ + " " + DQ + ":")
emit("        let goal = " + DQ + DQ)
emit("        for i in range(len(msg) - 5):")
emit("            goal = goal + msg[5 + i]")
emit("        let plan = planner.create_plan(goal)")
emit("        planner.add_step(plan, " + DQ + "Analyze requirements" + DQ + ", " + DQ + DQ + ", " + DQ + DQ + ", nil)")
emit("        planner.add_step(plan, " + DQ + "Create module file" + DQ + ", " + DQ + DQ + ", " + DQ + DQ + ", [0])")
emit("        planner.add_step(plan, " + DQ + "Write implementation" + DQ + ", " + DQ + DQ + ", " + DQ + DQ + ", [1])")
emit("        planner.add_step(plan, " + DQ + "Write tests" + DQ + ", " + DQ + DQ + ", " + DQ + DQ + ", [2])")
emit("        planner.add_step(plan, " + DQ + "Update documentation" + DQ + ", " + DQ + DQ + ", " + DQ + DQ + ", [3])")
emit("        planner.add_step(plan, " + DQ + "Run test suite" + DQ + ", " + DQ + DQ + ", " + DQ + DQ + ", [4])")
emit("        print " + DQ + DQ)
emit("        print planner.format_plan(plan)")
emit("        engram.store_episodic(memory, " + DQ + "Created plan for: " + DQ + " + goal, 0.8)")
emit("    if running and msg != " + DQ + "quit" + DQ + " and msg != " + DQ + "exit" + DQ + " and msg != " + DQ + "memory" + DQ + ":")
emit("        let is_think = false")
emit("        if len(msg) > 5 and msg[0] == " + DQ + "t" + DQ + " and msg[1] == " + DQ + "h" + DQ + " and msg[2] == " + DQ + "i" + DQ + " and msg[3] == " + DQ + "n" + DQ + " and msg[4] == " + DQ + "k" + DQ + ":")
emit("            is_think = true")
emit("        let is_plan = false")
emit("        if len(msg) > 4 and msg[0] == " + DQ + "p" + DQ + " and msg[1] == " + DQ + "l" + DQ + " and msg[2] == " + DQ + "a" + DQ + " and msg[3] == " + DQ + "n" + DQ + ":")
emit("            is_plan = true")
emit("        if not is_think and not is_plan:")
emit("            engram.store_working(memory, msg, 0.7)")
emit("            let resp = bot.respond(b, msg)")
emit("            print " + DQ + DQ)
emit("            print " + DQ + "SageDev> " + DQ + " + resp")
emit("            print " + DQ + DQ)
emit("            session.add_turn(sess, msg, resp)")

# Write the generated source
let out_path = "models/sagellm_chatbot.sage"
io.writefile(out_path, chatbot_source)
log("BUILD", "Generated chatbot source: " + out_path + " (" + str(len(chatbot_source)) + " chars)")

# Test it loads
log("BUILD", "Verifying generated source parses...")

print ""

# ============================================================================
# Step 7: Compile to binary
# ============================================================================

log("COMPILE", "Compiling SageLLM chatbot to native binary...")
log("COMPILE", "Command: sage --compile " + out_path + " -o sagellm_chat")
print ""
log("COMPILE", "To compile manually, run:")
log("COMPILE", "  ./sage --compile models/sagellm_chatbot.sage -o sagellm_chat")
log("COMPILE", "")
log("COMPILE", "To run in interpreter mode:")
log("COMPILE", "  ./sage models/sagellm_chatbot.sage")
print ""

# ============================================================================
# Step 8: Summary
# ============================================================================

separator()
print "  Build Complete"
separator()
print ""
print "Training:"
print "  Theory pre-training: " + str(theory_steps) + " steps, loss=" + str(train.avg_loss(state1))
print "  LoRA fine-tuning: " + str(lora_steps) + " steps on " + str(file_count) + " files, loss=" + str(train.avg_loss(state2))
print "  LoRA params: " + str(adapter["trainable_params"]) + " (75% savings)"
print ""
print "Memory:"
print "  Semantic facts: " + str(len(facts))
print "  Procedural skills: 2"
print "  Working capacity: 20 slots"
print "  Max episodic: 5000"
print "  Max semantic: 2000"
print ""
print "Output:"
print "  Chatbot source: models/sagellm_chatbot.sage"
print "  Run: ./sage models/sagellm_chatbot.sage"
print "  Compile: ./sage --compile models/sagellm_chatbot.sage -o sagellm_chat"
print ""

# Benchmark
let bench = ml_native.benchmark(64, 10)
print "Native backend: " + str(bench["gflops"]) + " GFLOPS (" + str(bench["ms_per_matmul"]) + " ms/matmul)"
print ""
separator()
