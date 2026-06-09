gc_disable()
# SageLLM Chatbot v2.0.0 - Self-contained (compiles with --compile-llvm)
# Compile: sage --compile-llvm models/sagellm_chatbot.sage -o sagellm_chat
# Run:     ./sagellm_chat   OR   sage models/sagellm_chatbot.sage

# === String utilities ===

proc contains(h, n):
    if len(n) > len(h):
        return false
    let hlen = len(h)
    let nlen = len(n)
    for i in range(hlen - nlen + 1):
        let found = true
        for j in range(nlen):
            if h[i + j] != n[j]:
                found = false
                break
        if found:
            return true
    return false

proc to_lower(s):
    let r = ""
    for i in range(len(s)):
        let c = ord(s[i])
        if c >= 65 and c <= 90:
            r = r + chr(c + 32)
        else:
            r = r + s[i]
    return r

proc starts_with(s, prefix):
    if len(prefix) > len(s):
        return false
    for i in range(len(prefix)):
        if s[i] != prefix[i]:
            return false
    return true

proc substr(s, start, count):
    let r = ""
    let end = start + count
    if end > len(s):
        end = len(s)
    for i in range(end - start):
        r = r + s[start + i]
    return r

# === Memory system (inline, no module dependency) ===

let sem_facts = []
let remembered = []
let history = []
let working = []
let procedures = []

# Load semantic knowledge
push(sem_facts, "Sage is an indentation-based systems programming language built in C with self-hosted compiler")
push(sem_facts, "127+ library modules across 11 subdirectories: graphics, os, net, crypto, ml, cuda, std, llm, agent, chat")
push(sem_facts, "Concurrent tri-color mark-sweep GC with SATB write barriers and sub-millisecond STW pauses")
push(sem_facts, "3 compiler backends: C codegen (--compile), LLVM IR (--compile-llvm), native assembly (--compile-native x86-64/aarch64/rv64)")
push(sem_facts, "Dotted imports: import os.fat resolves to lib/os/fat.sage")
push(sem_facts, "0 is TRUTHY - only false and nil are falsy")
push(sem_facts, "No escape sequences - use chr(10) for newline, chr(34) for double-quote")
push(sem_facts, "elif chains with 5+ branches malfunction - use if/continue instead")
push(sem_facts, "Class methods cannot see module-level let vars - pass as args")
push(sem_facts, "match is a reserved keyword")
push(sem_facts, "Lexer produces INDENT/DEDENT tokens for indentation-based blocks")
push(sem_facts, "Parser is recursive descent, parse_program() in compiler.c (shared by all backends)")
push(sem_facts, "AST has Expr and Stmt node types defined in ast.h")
push(sem_facts, "Tree-walking interpreter in src/c/interpreter.c")
push(sem_facts, "Values: numbers (double), strings, bools, nil, arrays, dicts, closures")
push(sem_facts, "GC 4 phases: root scan (STW ~50-200us), concurrent mark, remark (STW ~20-50us), concurrent sweep")
push(sem_facts, "Write barriers in env.c (env_define/env_assign) and value.c (array_set/dict_set)")
push(sem_facts, "gc_disable() required at top of heavy-allocation modules")
push(sem_facts, "Native ML backend: matmul, softmax, cross_entropy, adam_update, rms_norm, silu, gelu at 12+ GFLOPS")
push(sem_facts, "LLM library: 15 modules for building language models from scratch")
push(sem_facts, "SageGPT architecture: SwiGLU FFN + RoPE positional encoding + RMSNorm (Llama-style)")
push(sem_facts, "LoRA: low-rank adapters for efficient fine-tuning (rank 4-64)")
push(sem_facts, "DPO: Direct Preference Optimization for alignment without reward models")
push(sem_facts, "Engram: 4-tier memory (working FIFO, episodic timestamped, semantic permanent, procedural skills)")
push(sem_facts, "RAG: Retrieval-Augmented Generation with keyword extraction and document chunking")
push(sem_facts, "GGUF export/import for Ollama and llama.cpp compatibility")
push(sem_facts, "Quantization: int8 and int4 with per-group scaling and error analysis")
push(sem_facts, "Agent ReAct loop: observe -> think -> act -> reflect")
push(sem_facts, "Supervisor-Worker: control plane owns global state, specialist workers")
push(sem_facts, "Critic/validator: rule-based validators + LLM critics with iterative self-correction")
push(sem_facts, "Grammar-constrained decoding: token masking to prevent malformed output")
push(sem_facts, "Tree of Thoughts: MCTS-style search with state rollbacks")
push(sem_facts, "Semantic routing: keyword-based fast dispatch bypassing LLM for trivial commands")
push(sem_facts, "SFT trace recording: capture agent executions for fine-tuning data")
push(sem_facts, "Schema-validated tool calls with typed parameters and return types")
push(sem_facts, "Task planner: dependency DAG decomposition with tool assignments")
push(sem_facts, "6 built-in personas: SageDev, CodeReviewer, Teacher, Debugger, Architect, Assistant")
push(sem_facts, "Sessions: multi-session store, history tracking, text/JSON export")
push(sem_facts, "Vulkan graphics engine: 24 modules, ~4600 lines C, handle-table design")
push(sem_facts, "OpenGL 4.5 backend via gpu_api.c, GLSL shader support")
push(sem_facts, "PBR rendering: Cook-Torrance, IBL, point/directional lights, 8 material presets")
push(sem_facts, "Deferred rendering: G-buffer (4 MRT), SSAO (32 samples), SSR (64-step raymarch)")
push(sem_facts, "OS dev: FAT, ELF, PE, MBR, GPT, PCI, ACPI, UEFI, paging, IDT, serial, DTB, alloc, VFS (15 modules)")
push(sem_facts, "Networking: native socket/tcp/http/ssl + lib/net/ (URL, headers, request, server, websocket, DNS, IP)")
push(sem_facts, "Crypto: SHA-256, HMAC, Base64, RC4, XOR, PBKDF2, xoshiro256** PRNG, UUID v4 (6 modules)")
push(sem_facts, "Std: regex, datetime, log, argparse, fmt, testing, enum, trait, channel, threadpool, atomic (23 modules)")
push(sem_facts, "Build: make (Makefile) or cmake. Install: make install (prefix=/usr/local)")
push(sem_facts, "Tests: 1567+ self-hosted, 144 interpreter, 28 compiler tests. Run: make test-all")
push(sem_facts, "Library search: CWD, ./lib, source dir, /usr/local/share/sage/lib, SAGE_PATH env, exe-relative")
push(sem_facts, "GPU acceleration: gpu_accel module with auto-detection (GPU/CPU/NPU/TPU)")
push(sem_facts, "GGUF import: convert Ollama/llama.cpp models to SageGPT format (Q4_0/Q8_0 dequant)")

# Load procedural knowledge
push(procedures, "write_sage_code: Use proc for functions and class for OOP. Indent with spaces. Use let for variables. Import with dotted paths. Start heavy modules with gc_disable(). Use chr(10) for newline.")
push(procedures, "debug_sage: Check for reserved keyword match. Use chr() not escape sequences. Avoid 5+ elif branches. Add gc_disable() for GC segfaults. Run: bash tests/run_tests.sh")
push(procedures, "compile_sage: sage --compile file.sage -o out (C). sage --compile-llvm file.sage -o out (LLVM). sage --compile-native file.sage -o out (asm). Flags: -O0 to -O3, -g, --target x86-64|aarch64|rv64")
push(procedures, "add_builtin: Add strcmp dispatch in emit_call_expr() in compiler.c. Register in interpreter.c init_stdlib(). Add test. Update docs.")
push(procedures, "add_lib_module: Create lib/<category>/name.sage. Start with gc_disable() if needed. Add test in tests/. Update Makefile install. Update docs.")
push(procedures, "build_llm: Choose size via llm.config. Tokenize corpus. Pre-train with cosine LR. LoRA fine-tune. DPO alignment. RAG + Engram for knowledge. Quantize for deploy.")
push(procedures, "build_agent: Create with agent.core. Add tools. Define schemas. Use planner for DAG. Add critic. Semantic router for fast dispatch. Record traces for SFT.")
push(procedures, "fix_gc: Add gc_disable() at module top. Or gc_pin()/gc_unpin() around allocations. Check write barriers in env.c/value.c. Verify root coverage.")

# === Memory functions ===

proc mem_recall(query):
    let lq = to_lower(query)
    let results = []
    for i in range(len(sem_facts)):
        if contains(to_lower(sem_facts[i]), lq):
            push(results, sem_facts[i])
    for i in range(len(remembered)):
        if contains(to_lower(remembered[i]), lq):
            push(results, remembered[i])
    for i in range(len(procedures)):
        if contains(to_lower(procedures[i]), lq):
            push(results, procedures[i])
    return results

proc mem_store(fact):
    push(remembered, fact)

proc mem_summary():
    return "Memory: " + str(len(sem_facts)) + " facts, " + str(len(remembered)) + " remembered, " + str(len(procedures)) + " procedures, " + str(len(working)) + " working, " + str(len(history)) + " exchanges"

# === Chain-of-Thought Reasoning Engine (20 topics) ===

proc reason(question):
    let chain = []
    let lp = to_lower(question)

    # Step 1: Memory recall
    let mem = mem_recall(lp)
    if len(mem) > 0:
        push(chain, "Recalled " + str(len(mem)) + " relevant facts")

    # Step 2: Topic classification
    let topic = "general"
    if contains(lp, "llm") or contains(lp, "language model") or contains(lp, "transformer") or contains(lp, "lora") or contains(lp, "engram") or contains(lp, "neural") or contains(lp, "tokeniz"):
        topic = "llm"
    if topic == "general" and (contains(lp, "agent") or contains(lp, "react") or contains(lp, "supervisor") or contains(lp, "tool use")):
        topic = "agent"
    if topic == "general" and (contains(lp, "chatbot") or contains(lp, "persona") or contains(lp, "conversation") or contains(lp, "intent")):
        topic = "chatbot"
    if topic == "general" and (contains(lp, "crypto") or contains(lp, "sha") or contains(lp, "hash") or contains(lp, "encrypt")):
        topic = "crypto"
    if topic == "general" and (contains(lp, "network") or contains(lp, "http") or contains(lp, "socket") or contains(lp, "url") or contains(lp, "dns")):
        topic = "networking"
    if topic == "general" and (contains(lp, "baremetal") or contains(lp, "uefi") or contains(lp, "kernel") or contains(lp, "elf") or contains(lp, "pci") or contains(lp, "osdev")):
        topic = "osdev"
    if topic == "general" and (contains(lp, "tensor") or contains(lp, "machine learn") or contains(lp, "training") or contains(lp, "gradient")):
        topic = "ml"
    if topic == "general" and (contains(lp, "gpu") or contains(lp, "vulkan") or contains(lp, "opengl") or contains(lp, "shader") or contains(lp, "render")):
        topic = "graphics"
    if topic == "general" and (contains(lp, "regex") or contains(lp, "regular exp")):
        topic = "regex"
    if topic == "general" and (contains(lp, "gc ") or contains(lp, "garbage")):
        topic = "gc"
    if topic == "general" and (contains(lp, "compile") or contains(lp, "backend") or contains(lp, "emit")):
        topic = "compiler"
    if topic == "general" and (contains(lp, "for ") or contains(lp, "loop") or contains(lp, "while")):
        topic = "loops"
    if topic == "general" and (contains(lp, "import") or contains(lp, "module") or contains(lp, "library")):
        topic = "modules"
    if topic == "general" and (contains(lp, "class ") or contains(lp, "object") or contains(lp, "inherit")):
        topic = "oop"
    if topic == "general" and (contains(lp, "array") or contains(lp, "dict") or contains(lp, "data struct")):
        topic = "data"
    if topic == "general" and (contains(lp, "function") or contains(lp, "proc ") or contains(lp, "closure")):
        topic = "functions"
    if topic == "general" and (contains(lp, "error") or contains(lp, "exception") or contains(lp, "try ")):
        topic = "errors"
    if topic == "general" and (contains(lp, "test") or contains(lp, "debug") or contains(lp, "bug")):
        topic = "testing"
    if topic == "general" and (contains(lp, "thread") or contains(lp, "async") or contains(lp, "channel") or contains(lp, "concurrent")):
        topic = "concurrency"
    if topic == "general" and (contains(lp, "plan") or contains(lp, "how to build") or contains(lp, "steps")):
        topic = "planning"

    push(chain, "Topic: " + topic)

    # Step 3: Generate answer
    let answer = ""
    if topic == "llm":
        answer = "Sage LLM library (lib/llm/, 15 modules): config, tokenizer, embedding, attention, transformer, generate, train, agent, prompt, lora, quantize, engram, rag, dpo, gguf. SageGPT: SwiGLU+RoPE+RMSNorm architecture. Native C backend for matmul/softmax at 12+ GFLOPS. LoRA fine-tuning, DPO alignment, RAG retrieval, GGUF export for Ollama."
    if topic == "agent":
        answer = "Agent framework (lib/agent/, 12 modules): core (ReAct loop), tools (dispatch), planner (DAG decomposition), router (multi-agent), supervisor (control plane + workers), critic (validators + LLM review), schema (typed params), trace (SFT recording), grammar (constrained decoding), sandbox, tot (Tree of Thoughts MCTS), semantic_router (fast dispatch)."
    if topic == "chatbot":
        answer = "Chat framework (lib/chat/): bot.sage (intents, middleware, LLM wiring), persona.sage (6 built-in: SageDev, CodeReviewer, Teacher, Debugger, Architect, Assistant), session.sage (multi-session store, history, export). Create with bot.create(), add intents, apply persona."
    if topic == "crypto":
        answer = "Crypto library (lib/crypto/, 6 modules): hash (SHA-256, SHA-1, CRC-32), hmac (constant-time compare), encoding (Base64 standard+URL-safe, hex), cipher (XOR, RC4, PKCS7, CBC/CTR), rand (xoshiro256** PRNG, UUID v4, shuffle), password (PBKDF2-HMAC, hash/verify)."
    if topic == "networking":
        answer = "Networking: native modules (socket, tcp, http, ssl) + lib/net/ (8 modules): url (parse/build, percent encoding), headers (HTTP parse), request (HTTP client builder), server (TCP/HTTP routing), websocket (RFC 6455), mime (80+ types), dns (wire format), ip (IPv4, CIDR)."
    if topic == "osdev":
        answer = "OS dev (lib/os/, 15 modules): fat/fat_dir (FAT filesystem), elf/pe (binary parsers), mbr/gpt (partition tables), pci/acpi (hardware), uefi (EFI memory map), paging/idt (virtual memory, interrupts), serial (UART), dtb (device tree), alloc (kernel allocators), vfs (virtual filesystem)."
    if topic == "ml":
        answer = "ML libraries: lib/ml/ (tensor, nn, optim, loss, data, debug, viz, monitor) + lib/cuda/ (device, memory, kernel, stream). Native backend (ml_native): matmul, add, scale, relu, gelu, silu, sigmoid, softmax, layer_norm, rms_norm, cross_entropy, adam_update. 12+ GFLOPS."
    if topic == "graphics":
        answer = "GPU engine (24 modules): Vulkan backend (4600 lines C), OpenGL 4.5. Libraries: vulkan, gpu, math3d, mesh, renderer, pbr (Cook-Torrance), shadows (cascade), deferred (G-buffer, SSAO, SSR), taa, postprocess (bloom, tone mapping), scene, gltf 2.0, material, asset_cache, frame_graph."
    if topic == "regex":
        answer = "Sage regex (import std.regex): test(pattern, text), search(), find_all(), replace_all(), split_by(). Supports: . * + ? [] [^] ^ $ | and character classes."
    if topic == "gc":
        answer = "Concurrent tri-color mark-sweep GC: Phase 1 (STW ~50-200us) root scan + shade gray. Phase 2 (concurrent) process gray objects. Phase 3 (STW ~20-50us) remark + drain barrier. Phase 4 (concurrent) sweep white in batches. SATB write barrier. Control: gc_collect(), gc_enable(), gc_disable()."
    if topic == "compiler":
        answer = "3 backends: --compile (C codegen via cc/gcc/clang), --compile-llvm (LLVM IR via clang), --compile-native (direct x86-64/aarch64/rv64 assembly). Emit-only: --emit-c, --emit-llvm, --emit-asm. Optimization: -O0 to -O3. Debug: -g."
    if topic == "loops":
        answer = "Sage loops: for i in range(10): body. for item in array: body. while condition: body. break/continue. Avoid elif in for loops with break (use if/continue). Nested loops work fine."
    if topic == "modules":
        answer = "11 library categories with dotted imports: os (15), net (8), crypto (6), ml (8), cuda (4), std (23), llm (15), agent (12), chat (3), graphics (24), + root libs (9). 127+ modules total. Last path component becomes binding name."
    if topic == "oop":
        answer = "Sage OOP: class Name: with proc init(self): and methods. Inheritance: class Dog(Animal):. Methods get self. Instance fields via self.field = value. Note: class methods cannot see module-level let vars."
    if topic == "data":
        answer = "Arrays: let a = [1,2,3], push(a, 4), pop(a), a[0], slicing a[1:3]. Dicts: let d = {}, d[key] = val, dict_keys(d), dict_values(d), dict_has(d, key). Tuples: (1,2,3). Libs: arrays.sage (map, filter, sort), dicts.sage (merge, invert)."
    if topic == "functions":
        answer = "proc name(args): body. Return with return value. Closures: inner procs capture outer vars. First-class functions. No default args or variadic params."
    if topic == "errors":
        answer = "try: risky_code. catch e: handle(e). finally: cleanup(). raise to throw. Rich error reporting in parser with source context and hints (src/sage/errors.sage)."
    if topic == "testing":
        answer = "Tests: bash tests/run_tests.sh (144 interpreter), make test (28 compiler), make test-selfhost (1567+), make test-all. Debug: gc_disable() for segfaults, chr() not escapes, avoid 5+ elif."
    if topic == "concurrency":
        answer = "Concurrency: import thread (OS threads + mutexes), async proc f(): (async/await), std.channel (Go-style), std.atomic, std.rwlock, std.condvar, std.threadpool (worker pools)."
    if topic == "planning":
        answer = "Development plan: 1) Define goal, 2) Create module in lib/<category>/, 3) Start with gc_disable() if needed, 4) Implement, 5) Write tests, 6) Update Makefile + docs, 7) Run: bash tests/run_tests.sh."

    if len(answer) == 0:
        if len(mem) > 0:
            answer = "Based on my knowledge: " + mem[0]
        else:
            answer = "I can help with: loops, imports, classes, GC, compiler, data, functions, errors, testing, concurrency, planning, LLM, agents, chatbot, crypto, networking, OS dev, ML, graphics, regex."

    push(chain, "Answering about " + topic)

    # Record in history
    push(history, "Q: " + question)
    push(history, "A: " + answer)

    let result = {}
    result["chain"] = chain
    result["answer"] = answer
    return result

proc show_chain(r):
    let ch = r["chain"]
    for ci in range(len(ch)):
        print "  Thought " + str(ci + 1) + ": " + ch[ci]
    print "  Answer: " + r["answer"]

# === Main loop ===

let persona_name = "SageDev"

print "============================================"
print "  SageLLM Chatbot v2.0.0 (Medium | 16K)"
print "  SageGPT: SwiGLU + RoPE + RMSNorm"
print "  CoT + Memory + 20 Knowledge Domains"
print "============================================"
print "Hello! I am " + persona_name + " v2.0. Ask me about Sage."
print "Commands: quit, memory, remember, recall, think, plan, personas, help"
print ""

let running = true
while running:
    let msg = input("You> ")
    if msg == "quit" or msg == "exit":
        running = false
        print persona_name + "> Goodbye. " + str(len(history)) + " exchanges recorded. Happy coding!"

    if running and msg == "help":
        print "  Commands:"
        print "    quit          - Exit the chatbot"
        print "    memory        - Show memory stats"
        print "    remember <f>  - Store a fact"
        print "    recall <q>    - Search memory"
        print "    think <q>     - Show reasoning chain"
        print "    plan <goal>   - Generate development plan"
        print "    personas      - List available personas"
        print "    <name>        - Switch persona (sagedev, teacher, debugger, architect)"
        print ""

    if running and msg == "memory":
        print "  " + mem_summary()
        if len(working) > 0:
            print "  Recent topics:"
            let wstart = 0
            if len(working) > 5:
                wstart = len(working) - 5
            for wi in range(len(working) - wstart):
                print "    - " + working[wstart + wi]
        print ""

    if running and starts_with(msg, "remember "):
        let fact = substr(msg, 9, len(msg) - 9)
        mem_store(fact)
        print "  Remembered: " + fact
        print ""

    if running and starts_with(msg, "recall "):
        let rq = substr(msg, 7, len(msg) - 7)
        let results = mem_recall(rq)
        if len(results) > 0:
            let limit = len(results)
            if limit > 5:
                limit = 5
            for ri in range(limit):
                print "  [" + str(ri + 1) + "] " + results[ri]
        else:
            print "  No memories found for: " + rq
        print ""

    if running and starts_with(msg, "think "):
        let tq = substr(msg, 6, len(msg) - 6)
        print ""
        show_chain(reason(tq))
        push(working, tq)
        print ""

    if running and starts_with(msg, "plan "):
        let goal = substr(msg, 5, len(msg) - 5)
        print ""
        print "  Plan for: " + goal
        print "  ---"
        print "  1. Analyze requirements and constraints"
        print "  2. Design architecture (choose lib/<category>/)"
        print "  3. Create module file with gc_disable() if needed"
        print "  4. Write implementation"
        print "  5. Write tests in tests/ directory"
        print "  6. Update Makefile install section"
        print "  7. Update README and documentation"
        print "  8. Run: bash tests/run_tests.sh"
        print "  9. Run: make test-selfhost"
        push(history, "Plan: " + goal)
        print ""

    if running and msg == "personas":
        print "  Available personas:"
        print "    sagedev   - Expert Sage developer (default)"
        print "    teacher   - Patient educator, explains step by step"
        print "    debugger  - Bug hunter, focuses on root causes"
        print "    architect - System designer, high-level overview"
        print ""

    if running and msg == "teacher":
        persona_name = "Teacher"
        print "  Switched to Teacher persona."
    if running and msg == "debugger":
        persona_name = "Debugger"
        print "  Switched to Debugger persona."
    if running and msg == "architect":
        persona_name = "Architect"
        print "  Switched to Architect persona."
    if running and msg == "sagedev":
        persona_name = "SageDev"
        print "  Switched to SageDev persona."

    # Default: answer the question
    if running and msg != "quit" and msg != "exit" and msg != "memory" and msg != "help" and msg != "personas" and msg != "teacher" and msg != "debugger" and msg != "architect" and msg != "sagedev":
        let is_cmd = false
        if starts_with(msg, "think "):
            is_cmd = true
        if starts_with(msg, "plan "):
            is_cmd = true
        if starts_with(msg, "remember "):
            is_cmd = true
        if starts_with(msg, "recall "):
            is_cmd = true
        if not is_cmd:
            push(working, msg)
            let r = reason(msg)
            print ""
            print persona_name + "> " + r["answer"]
            print ""
