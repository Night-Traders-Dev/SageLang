gc_disable()
# ============================================================================
# Comprehensive Training Data Collector
# Gathers ALL training data tiers for SageLLM:
#   Tier 1: Sage codebase, tests, docs
#   Tier 2: Compiler theory, language design, code patterns
#   Tier 3: Bug patterns, performance, API design
#   Tier 4: Agentic traces, debugging, code review
#
# Usage: sage models/data/collect_all.sage
# Output: models/data/corpus_full.txt
# ============================================================================

import io

let NL = chr(10)
let SEP = "<|end|>" + NL
let corpus = ""
let stats = {}
stats["files"] = 0
stats["chars"] = 0
stats["sections"] = 0

proc add_section(tag, content):
    if content == nil:
        return
    if len(content) == 0:
        return
    corpus = corpus + "<|" + tag + "|>" + NL + content + NL + SEP
    stats["sections"] = stats["sections"] + 1
    stats["chars"] = stats["chars"] + len(content)

proc load_file(path, tag):
    let content = io.readfile(path)
    if content != nil:
        add_section(tag + ":" + path, content)
        stats["files"] = stats["files"] + 1
        return true
    return false

proc log(msg):
    print "[COLLECT] " + msg

# ============================================================================
# TIER 1: Sage Codebase (critical)
# ============================================================================

log("=== Tier 1: Sage Codebase ===")

# Self-hosted compiler
let sage_src = ["src/sage/token.sage", "src/sage/lexer.sage", "src/sage/ast.sage", "src/sage/parser.sage", "src/sage/interpreter.sage", "src/sage/compiler.sage", "src/sage/codegen.sage", "src/sage/llvm_backend.sage", "src/sage/formatter.sage", "src/sage/linter.sage", "src/sage/lsp.sage", "src/sage/module.sage", "src/sage/errors.sage", "src/sage/sage.sage", "src/sage/gc.sage", "src/sage/value.sage", "src/sage/pass.sage", "src/sage/constfold.sage", "src/sage/dce.sage", "src/sage/inline.sage", "src/sage/diagnostic.sage", "src/sage/heartbeat.sage", "src/sage/environment.sage", "src/sage/stdlib.sage", "src/sage/typecheck.sage"]
let loaded = 0
for i in range(len(sage_src)):
    if load_file(sage_src[i], "sage_compiler"):
        loaded = loaded + 1
log("  Self-hosted compiler: " + str(loaded) + " files")

# C implementation
let c_src = ["src/c/lexer.c", "src/c/parser.c", "src/c/interpreter.c", "src/c/compiler.c", "src/c/gc.c", "src/c/value.c", "src/c/env.c", "src/c/module.c", "src/c/stdlib.c", "src/c/codegen.c", "src/c/llvm_backend.c", "src/c/ml_backend.c", "src/c/net.c", "src/c/graphics.c", "src/c/gpu_api.c", "src/c/lsp.c"]
loaded = 0
for i in range(len(c_src)):
    if load_file(c_src[i], "c_implementation"):
        loaded = loaded + 1
log("  C implementation: " + str(loaded) + " files")

# Headers
let headers = ["include/gc.h", "include/value.h", "include/env.h", "include/module.h", "include/ast.h", "include/lexer.h", "include/parser.h", "include/interpreter.h", "include/compiler.h"]
loaded = 0
for i in range(len(headers)):
    if load_file(headers[i], "c_header"):
        loaded = loaded + 1
log("  C headers: " + str(loaded) + " files")

# All library modules
let lib_dirs = [["lib", "lib_core"], ["lib/os", "lib_os"], ["lib/net", "lib_net"], ["lib/crypto", "lib_crypto"], ["lib/ml", "lib_ml"], ["lib/cuda", "lib_cuda"], ["lib/std", "lib_std"], ["lib/llm", "lib_llm"], ["lib/agent", "lib_agent"], ["lib/chat", "lib_chat"], ["lib/graphics", "lib_graphics"]]

# Known files per directory
let lib_files = ["arrays.sage", "dicts.sage", "strings.sage", "iter.sage", "json.sage", "math.sage", "stats.sage", "utils.sage", "assert.sage"]
let os_files = ["fat.sage", "fat_dir.sage", "elf.sage", "mbr.sage", "gpt.sage", "pe.sage", "pci.sage", "uefi.sage", "acpi.sage", "paging.sage", "idt.sage", "serial.sage", "dtb.sage", "alloc.sage", "vfs.sage"]
let net_files = ["url.sage", "headers.sage", "request.sage", "server.sage", "websocket.sage", "mime.sage", "dns.sage", "ip.sage"]
let crypto_files = ["hash.sage", "hmac.sage", "encoding.sage", "cipher.sage", "rand.sage", "password.sage"]
let ml_files = ["tensor.sage", "nn.sage", "optim.sage", "loss.sage", "data.sage", "debug.sage", "viz.sage", "monitor.sage"]
let std_files = ["regex.sage", "datetime.sage", "log.sage", "argparse.sage", "compress.sage", "process.sage", "unicode.sage", "fmt.sage", "testing.sage", "enum.sage", "trait.sage", "signal.sage", "db.sage", "channel.sage", "threadpool.sage", "atomic.sage", "rwlock.sage", "condvar.sage", "debug.sage", "profiler.sage", "docgen.sage", "build.sage", "interop.sage"]
let llm_files = ["config.sage", "tokenizer.sage", "embedding.sage", "attention.sage", "transformer.sage", "generate.sage", "train.sage", "agent.sage", "prompt.sage", "lora.sage", "quantize.sage", "engram.sage", "rag.sage", "dpo.sage", "gguf.sage"]
let agent_files = ["core.sage", "tools.sage", "planner.sage", "router.sage", "supervisor.sage", "critic.sage", "schema.sage", "trace.sage", "grammar.sage", "sandbox.sage", "tot.sage", "semantic_router.sage"]
let chat_files = ["bot.sage", "session.sage", "persona.sage"]

let all_lib_sets = [["lib", lib_files], ["lib/os", os_files], ["lib/net", net_files], ["lib/crypto", crypto_files], ["lib/ml", ml_files], ["lib/std", std_files], ["lib/llm", llm_files], ["lib/agent", agent_files], ["lib/chat", chat_files]]

loaded = 0
for i in range(len(all_lib_sets)):
    let dir = all_lib_sets[i][0]
    let files = all_lib_sets[i][1]
    for j in range(len(files)):
        if load_file(dir + "/" + files[j], "lib"):
            loaded = loaded + 1
log("  Library modules: " + str(loaded) + " files")

# Documentation
let docs = ["documentation/SageLang_Guide.md", "documentation/GC_Guide.md", "documentation/LLM_Guide.md", "documentation/Agent_Chat_Guide.md", "documentation/StdLib_Guide.md", "documentation/Networking_Guide.md", "documentation/Cryptography_Guide.md", "documentation/Baremetal_OSDev_UEFI_Guide.md", "documentation/Vulkan_GPU_Guide.md", "documentation/ML_CUDA_Guide.md", "documentation/Import_Semantics.md", "documentation/FAT_Filesystem_Guide.md", "documentation/Bytecode_VM_Sketch.md"]
loaded = 0
for i in range(len(docs)):
    if load_file(docs[i], "documentation"):
        loaded = loaded + 1
log("  Documentation: " + str(loaded) + " files")

# Build files
load_file("Makefile", "build_system")
load_file("CMakeLists.txt", "build_system")
log("  Build system: 2 files")

# Tests (as supervised training data)
let test_dirs = ["tests/26_stdlib"]
let test_files_list = ["regex_test.sage", "datetime_test.sage", "fmt_test.sage", "enum_test.sage", "channel_test.sage", "db_test.sage", "tensor_test.sage", "nn_test.sage", "llm_config_test.sage", "llm_tokenizer_test.sage", "llm_agent_test.sage", "llm_rag_test.sage", "agent_core_test.sage", "agent_supervisor_test.sage", "agent_critic_test.sage", "agent_grammar_test.sage", "agent_sandbox_test.sage", "fat_boot_parse.sage", "elf_parse.sage", "mbr_parse.sage", "pci_parse.sage", "url_test.sage", "ip_test.sage", "hash_test.sage", "encoding_test.sage"]
loaded = 0
for i in range(len(test_files_list)):
    if load_file("tests/26_stdlib/" + test_files_list[i], "test_case"):
        loaded = loaded + 1
log("  Test cases: " + str(loaded) + " files")

# ============================================================================
# TIER 2: Programming Knowledge (existing data files)
# ============================================================================

log("=== Tier 2: Programming Knowledge ===")

load_file("models/data/programming_languages.txt", "theory")
log("  Programming language theory: loaded")

load_file("models/data/multilang_examples.txt", "multilang")
log("  Multi-language examples: loaded")

load_file("models/data/natural_language.txt", "nlp")
log("  Natural language / NLP: loaded")

# ============================================================================
# TIER 2+: Extended compiler and language design knowledge
# ============================================================================

add_section("compiler_internals", "# Sage Compiler Internals" + NL + NL + "## Compilation Pipeline" + NL + "1. Source code -> Lexer (lexer.c) -> Token stream" + NL + "2. Token stream -> Parser (parser.c) -> AST" + NL + "3. AST -> Optimization passes (pass.c, constfold.c, dce.c, inline.c)" + NL + "4. Optimized AST -> Backend:" + NL + "   - C backend (compiler.c): AST -> C source -> gcc/clang -> binary" + NL + "   - LLVM backend (llvm_backend.c): AST -> LLVM IR -> clang -> binary" + NL + "   - Native backend (codegen.c): AST -> VInst IR -> x86-64/aarch64/rv64 assembly" + NL + "   - Bytecode VM (vm/bytecode.c): AST -> bytecode -> stack-based VM" + NL + NL + "## Key Design Decisions" + NL + "- Indentation-based: INDENT/DEDENT tokens from lexer (no braces)" + NL + "- Dynamic typing: Values are tagged unions (VAL_NUMBER, VAL_STRING, etc.)" + NL + "- Concurrent GC: Tri-color mark-sweep with SATB write barriers" + NL + "- Module system: Dotted paths (os.fat -> lib/os/fat.sage)" + NL + "- Self-hosting: Sage compiler written in Sage (src/sage/)" + NL + NL + "## Parser Architecture" + NL + "- Recursive descent with 12 precedence levels (Pratt-style)" + NL + "- Indentation tracking via stack in lexer" + NL + "- Error recovery: skip to next statement boundary" + NL + "- Produces linked list of Stmt nodes" + NL + NL + "## Value Representation" + NL + "- Tagged union: struct { int type; union { double number; char* string; ArrayValue* array; ... } }" + NL + "- 16 value types: nil, number, bool, string, array, dict, tuple, function, native, generator, class, instance, exception, module, clib, pointer, thread, mutex" + NL + "- GC header prepended to heap-allocated values" + NL + NL + "## Environment Model" + NL + "- Linked list of EnvNode (name -> value pairs)" + NL + "- Parent pointer for lexical scoping" + NL + "- Closures capture environment pointer at definition time" + NL + "- Module environments isolated, accessible via import" + NL)

add_section("optimization_passes", "# Sage Optimization Passes" + NL + NL + "## Constant Folding (constfold.c)" + NL + "- Evaluates constant expressions at compile time: 2 + 3 -> 5" + NL + "- Handles: arithmetic, string concatenation, boolean logic" + NL + "- Folds constant conditions: if true -> unconditional, if false -> remove" + NL + "- Guards against infinity, NaN, and 64KB string limit" + NL + NL + "## Dead Code Elimination (dce.c)" + NL + "- Removes unused let bindings and proc definitions" + NL + "- Removes unreachable code after return/break/continue" + NL + "- Uses dynamic name buffers (no 256-byte truncation)" + NL + NL + "## Function Inlining (inline.c)" + NL + "- Inlines single-return non-recursive procs" + NL + "- Parameter substitution with AST cloning" + NL + "- Controlled by -O level flags" + NL + NL + "## Pass Infrastructure (pass.c)" + NL + "- PassEntry array with name, level, function pointer" + NL + "- run_passes() applies passes based on -O0 through -O3" + NL + "- Deep AST cloning for async_proc parameters" + NL)

add_section("gc_internals", "# Sage GC Internals" + NL + NL + "## Concurrent Tri-Color Mark-Sweep" + NL + "Colors: WHITE=0 (unreachable), GRAY=1 (pending), BLACK=2 (scanned)" + NL + NL + "## 4-Phase Collection" + NL + "Phase 1 (STW ~50-200us): Root scan" + NL + "  - Reset all objects to WHITE" + NL + "  - Shade root objects GRAY (environments, VM stack, modules)" + NL + "  - Enable SATB write barrier" + NL + NL + "Phase 2 (Concurrent): Mark" + NL + "  - Process gray objects from mark stack" + NL + "  - For each gray object: scan children, shade them gray, turn parent black" + NL + "  - Mutator runs freely; write barrier catches reference overwrites" + NL + NL + "Phase 3 (STW ~20-50us): Remark" + NL + "  - Re-scan roots for new references created during concurrent mark" + NL + "  - Drain any barrier-shaded objects" + NL + "  - Disable write barrier" + NL + NL + "Phase 4 (Concurrent): Sweep" + NL + "  - Free WHITE objects in 256-object batches" + NL + "  - Reset surviving objects to WHITE for next cycle" + NL + NL + "## SATB Write Barrier" + NL + "Before overwriting a reference field:" + NL + "  GC_WRITE_BARRIER(old_value)" + NL + "If old_value is WHITE, shade it GRAY (push to mark stack)" + NL + "This ensures no live object is missed during concurrent marking" + NL + NL + "## Insertion Points" + NL + "  env_define(), env_assign() - environment variable updates" + NL + "  array_set() - array element overwrite" + NL + "  dict_set() - dictionary entry update" + NL + NL + "## Allocated-Black Invariant" + NL + "Objects allocated during marking are born BLACK" + NL + "They survive the current cycle without needing to be traced" + NL)

add_section("language_gotchas", "# Sage Language Gotchas and Patterns" + NL + NL + "## Truthy/Falsy Rules" + NL + "- 0 is TRUTHY (unlike Python/JS)" + NL + "- Only false and nil are falsy" + NL + "- All numbers (including 0), strings (including empty), arrays, dicts are truthy" + NL + NL + "## No Escape Sequences" + NL + "- Strings are raw: no backslash-n, backslash-t" + NL + "- Use chr(10) for newline, chr(9) for tab, chr(34) for double-quote" + NL + "- Use chr(92) for backslash" + NL + NL + "## elif Chain Limit" + NL + "- elif chains with 5+ branches malfunction" + NL + "- Use sequential if/continue pattern instead:" + NL + "  for c in cases:" + NL + "      if c == 1:" + NL + "          handle1()" + NL + "          continue" + NL + "      if c == 2:" + NL + "          handle2()" + NL + "          continue" + NL + NL + "## For Loop Break Pattern" + NL + "- Setting loop variable (i = len(arr)) does NOT break the loop" + NL + "- Use a guard flag: if not found and condition: found = true" + NL + NL + "## Class Method Scoping" + NL + "- Class methods cannot see module-level let variables" + NL + "- Pass values as arguments or hardcode them" + NL + NL + "## Reserved Keywords" + NL + "- match is reserved (cannot use as variable name)" + NL + "- Use is_match, matched, etc. instead" + NL + NL + "## GC Safety" + NL + "- Heavy allocation modules: start with gc_disable()" + NL + "- Multi-step allocations: wrap with gc_pin()/gc_unpin()" + NL + "- The crypto, ml, llm modules all use gc_disable()" + NL + NL + "## Module Import Binding" + NL + "- import os.fat binds as fat (last component)" + NL + "- Use import os.fat as my_fat to override binding name" + NL + "- Native modules (math, io, sys, thread) are C-built, always available" + NL)

# ============================================================================
# TIER 3: Bug Patterns, Performance, API Design
# ============================================================================

log("=== Tier 3: Bug Patterns and Best Practices ===")

add_section("bug_patterns", "# Common Bug Patterns in Sage Development" + NL + NL + "## GC Segfaults" + NL + "Symptom: Segfault during heavy allocation (crypto hashing, tensor ops)" + NL + "Cause: GC triggers during deeply-nested interpreter state, root coverage gap" + NL + "Fix: gc_disable() at module top, or gc_pin()/gc_unpin() around multi-step allocs" + NL + NL + "## C Backend Compilation Errors" + NL + "Symptom: cannot find module X" + NL + "Cause: Native modules (io, math, sys) have no .sage files" + NL + "Fix: is_native_module() check skips them in compiler" + NL + NL + "Symptom: unknown call target chr" + NL + "Cause: C backend missing builtin emit for chr/ord/type" + NL + "Fix: Added to emit_call_expr() and C runtime prelude" + NL + NL + "Symptom: procedure X is redefined with N parameters" + NL + "Cause: Multiple imported modules define procs with same name" + NL + "Fix: Silently keep first definition (namespace flattening)" + NL + NL + "Symptom: sage_index_set undefined" + NL + "Cause: Dict assignment (d[key] = val) not in C runtime prelude" + NL + "Fix: Added sage_index_set to prelude" + NL + NL + "## Integer Printing" + NL + "Symptom: Large numbers print as scientific notation (4.1943e+06)" + NL + "Cause: printf format %g switches to scientific for large values" + NL + "Fix: Check if value == (long long)value, use %lld for whole numbers" + NL + NL + "## BPE Tokenizer Crashes" + NL + "Symptom: Invalid index assignment errors during BPE training" + NL + "Cause: Array grows beyond bounds during merge step" + NL + "Fix: Use push() for new elements, check bounds before assignment" + NL + NL + "## Module Path Resolution" + NL + "Symptom: Cannot find module when running from different directory" + NL + "Cause: Search paths were only ./lib (relative to CWD)" + NL + "Fix: Added source dir, install path, SAGE_PATH env, exe-relative paths" + NL)

add_section("performance_patterns", "# Performance Optimization Patterns" + NL + NL + "## Native Backend (ml_native)" + NL + "- C-optimized matmul: 12+ GFLOPS on 64x64 without BLAS" + NL + "- Key functions: matmul, softmax, cross_entropy, adam_update, rms_norm" + NL + "- Eliminates interpreter overhead for ML inner loops" + NL + NL + "## GC Performance" + NL + "- Concurrent marking: sub-millisecond STW pauses" + NL + "- Root scan: ~50-200us, Remark: ~20-50us" + NL + "- Incremental sweep: 256 objects per batch" + NL + "- Threshold adaptation: less aggressive after low-reclamation cycles" + NL + NL + "## Interpreter Optimization" + NL + "- Profile hot paths: gc_alloc, env_get, array_push" + NL + "- Reduce allocation: reuse arrays, cache K constants (SHA-256)" + NL + "- Minimize GC pressure: gc_pin() around critical sections" + NL + NL + "## Compilation Pipeline" + NL + "- C backend: leverages gcc -O2 for optimized output" + NL + "- LLVM backend: SSA form enables advanced optimizations" + NL + "- Native backend: direct register allocation, no interpreter overhead" + NL + "- Bytecode VM: 10-100x faster than tree-walking via flat dispatch" + NL)

add_section("api_design", "# API Design Principles for Sage Libraries" + NL + NL + "## Naming Conventions" + NL + "- Functions: snake_case (create_buffer, parse_header)" + NL + "- Constants: UPPER_CASE (VAL_STRING, GC_WHITE)" + NL + "- Modules: lowercase (os.fat, net.url)" + NL + "- Classes: PascalCase (ModuleCache, GCHeader)" + NL + NL + "## Return Values" + NL + "- Success: return the result directly" + NL + "- Failure: return nil (not exceptions, for performance)" + NL + "- Complex results: return a dict with named fields" + NL + "- Boolean results: return true/false" + NL + NL + "## Module Structure" + NL + "- Start with gc_disable() if heavy allocation" + NL + "- Group related functions with comment headers" + NL + "- Export all public functions at module level" + NL + "- Utility functions: prefix with _ or put at end" + NL + NL + "## Error Handling in Libraries" + NL + "- Never crash: return nil or error dict" + NL + "- Validate inputs at boundaries" + NL + "- Provide context in error messages" + NL + "- Document gotchas in comments" + NL)

# ============================================================================
# TIER 4: Agentic Training Data
# ============================================================================

log("=== Tier 4: Agentic Patterns ===")

add_section("agentic_patterns", "# Agentic AI Patterns" + NL + NL + "## Supervisor-Worker Architecture" + NL + "- Supervisor: owns global state, routes tasks, validates transitions" + NL + "- Workers: intentionally narrow scope (one task type each)" + NL + "- Workflow: sequential steps with dependency tracking" + NL + "- Self-healing: error context appended to retries" + NL + NL + "## Verification Loops" + NL + "- Rule-based: not_empty, length bounds, keyword containment" + NL + "- LLM critic: semantic review with APPROVE/REJECT" + NL + "- Composite: rules first (fast) then critic (semantic)" + NL + "- Self-correction: failed output + feedback -> retry" + NL + NL + "## Grammar-Constrained Decoding" + NL + "- Validate output format before accepting" + NL + "- Tool calls: TOOL: name(args) / ANSWER: text" + NL + "- JSON: matching braces/brackets" + NL + "- Sage code: no escape sequences, no 5+ elif" + NL + "- Constrained wrapper: auto-retry with error feedback" + NL + NL + "## Program-Aided Reasoning" + NL + "- Extract code blocks from LLM output" + NL + "- Safety check: block FFI, memory, assembly calls" + NL + "- Execute in sandbox, inject result back to context" + NL + "- Deterministic math eval: offload to compiler" + NL + NL + "## Tree of Thoughts" + NL + "- Generate N candidate next steps" + NL + "- Score each with evaluator function" + NL + "- Follow best path, rollback on dead ends" + NL + "- BFS or best-first search over reasoning tree" + NL + NL + "## Semantic Routing" + NL + "- Match trivial commands to deterministic handlers" + NL + "- Bypass LLM entirely for known commands" + NL + "- Sub-millisecond latency, zero hallucination" + NL + "- Complex queries fall through to full agent" + NL + NL + "## SFT Trace Collection" + NL + "- Record: task, thoughts, tool calls, outputs" + NL + "- Generate: prompt->completion pairs for SFT" + NL + "- Generate: message format for chat fine-tuning" + NL + "- Generate: chosen/rejected pairs for DPO" + NL + NL + "## Tool Design Best Practices" + NL + "- Narrow scope: read_file not execute_bash" + NL + "- Typed interfaces: validate args before execution" + NL + "- Schema registry: bounded execution surface" + NL + "- Descriptive names: the LLM reads tool descriptions" + NL)

# ============================================================================
# TIER 2+: Synthetic instruction/response pairs
# ============================================================================

log("=== Generating Synthetic Training Pairs ===")

# Generate instruction/response pairs from the codebase
let pairs = []

proc add_pair(instruction, response):
    add_section("instruction_pair", "INSTRUCTION: " + instruction + NL + "RESPONSE: " + response)
    push(pairs, instruction)

# Sage coding tasks
add_pair("Write a Sage function that reverses a string", "proc reverse(s):" + NL + "    let result = " + chr(34) + chr(34) + NL + "    let i = len(s) - 1" + NL + "    while i >= 0:" + NL + "        result = result + s[i]" + NL + "        i = i - 1" + NL + "    return result")

add_pair("How do I read a file in Sage?", "import io" + NL + "let content = io.readfile(" + chr(34) + "path/to/file.txt" + chr(34) + ")" + NL + "if content != nil:" + NL + "    print content" + NL + "else:" + NL + "    print " + chr(34) + "File not found" + chr(34))

add_pair("Write a binary search in Sage", "proc binary_search(arr, target):" + NL + "    let lo = 0" + NL + "    let hi = len(arr) - 1" + NL + "    while lo <= hi:" + NL + "        let mid = ((lo + hi) / 2) | 0" + NL + "        if arr[mid] == target:" + NL + "            return mid" + NL + "        if arr[mid] < target:" + NL + "            lo = mid + 1" + NL + "        else:" + NL + "            hi = mid - 1" + NL + "    return -1")

add_pair("How do I create a class with inheritance in Sage?", "class Animal:" + NL + "    proc init(self, name):" + NL + "        self.name = name" + NL + "    proc speak(self):" + NL + "        print self.name + " + chr(34) + " makes a sound" + chr(34) + NL + NL + "class Dog(Animal):" + NL + "    proc speak(self):" + NL + "        print self.name + " + chr(34) + " barks" + chr(34) + NL + NL + "let d = Dog(" + chr(34) + "Rex" + chr(34) + ")" + NL + "d.speak()  # Rex barks")

add_pair("Write a test file for a stack implementation", "gc_disable()" + NL + "# EXPECT: 3" + NL + "# EXPECT: 3" + NL + "# EXPECT: 2" + NL + NL + "let stack = []" + NL + "push(stack, 1)" + NL + "push(stack, 2)" + NL + "push(stack, 3)" + NL + "print len(stack)" + NL + "print pop(stack)" + NL + "print len(stack)")

add_pair("How do I use the regex library?", "import std.regex" + NL + NL + "# Test if pattern matches" + NL + "print regex.test(" + chr(34) + "[0-9]+" + chr(34) + ", " + chr(34) + "abc123" + chr(34) + ")  # true" + NL + NL + "# Find first match" + NL + "let m = regex.search(" + chr(34) + "[a-z]+" + chr(34) + ", " + chr(34) + "hello world" + chr(34) + ")" + NL + "print m[" + chr(34) + "text" + chr(34) + "]  # hello" + NL + NL + "# Replace all" + NL + "print regex.replace_all(" + chr(34) + "[0-9]" + chr(34) + ", " + chr(34) + "a1b2c3" + chr(34) + ", " + chr(34) + "X" + chr(34) + ")  # aXbXcX")

add_pair("How do I handle errors in Sage?", "try:" + NL + "    let result = risky_operation()" + NL + "    print result" + NL + "catch e:" + NL + "    print " + chr(34) + "Error: " + chr(34) + " + e" + NL + "finally:" + NL + "    cleanup()" + NL + NL + "# Raise your own errors:" + NL + "proc divide(a, b):" + NL + "    if b == 0:" + NL + "        raise " + chr(34) + "Division by zero" + chr(34) + NL + "    return a / b")

add_pair("How do I use the LLM library to build a chatbot?", "import llm.engram" + NL + "import chat.bot" + NL + "import chat.persona" + NL + NL + "# Memory" + NL + "let memory = engram.create(nil)" + NL + "engram.store_semantic(memory, " + chr(34) + "I am a helpful assistant" + chr(34) + ", 1.0)" + NL + NL + "# LLM function" + NL + "proc my_llm(prompt):" + NL + "    let ctx = engram.build_context(memory, prompt, 3)" + NL + "    return " + chr(34) + "Response based on: " + chr(34) + " + ctx" + NL + NL + "# Create bot" + NL + "let b = bot.create(" + chr(34) + chr(34) + ", " + chr(34) + chr(34) + ", my_llm)" + NL + "persona.apply_persona(b, persona.sage_developer())" + NL + "let response = bot.respond(b, " + chr(34) + "hello" + chr(34) + ")")

add_pair("What is the difference between import and from import?", "import math            # Binds as namespace: math.sin(), math.pi" + NL + "from math import sin   # Imports specific item: sin() directly" + NL + "import os.fat          # Dotted path: binds as fat" + NL + "import os.fat as fs    # Binds as fs instead" + NL + NL + "# Native modules (math, io, sys, thread) are C-built" + NL + "# Library modules (lib/**/*.sage) are Sage source")

add_pair("How do I add a new module to Sage?", "# 1. Create the file:" + NL + "#    lib/<category>/my_module.sage" + NL + NL + "# 2. Start with gc_disable() if heavy allocation:" + NL + "gc_disable()" + NL + NL + "# 3. Write your functions:" + NL + "proc my_function(arg):" + NL + "    return arg * 2" + NL + NL + "# 4. Add a test:" + NL + "#    tests/26_stdlib/my_module_test.sage" + NL + "#    # EXPECT: 42" + NL + "#    import category.my_module" + NL + "#    print my_module.my_function(21)" + NL + NL + "# 5. Update Makefile install section" + NL + "# 6. Run: bash tests/run_tests.sh")

log("  Synthetic pairs: " + str(len(pairs)))

# ============================================================================
# Save corpus
# ============================================================================

log("")
log("=== Corpus Summary ===")
log("  Sections: " + str(stats["sections"]))
log("  Files loaded: " + str(stats["files"]))
log("  Total characters: " + str(stats["chars"]))
log("  Estimated tokens: ~" + str((stats["chars"] / 4) | 0))

let out_path = "models/data/corpus_full.txt"
io.writefile(out_path, corpus)
log("  Saved to: " + out_path)
log("")
log("Done. Use this corpus with:")
log("  sage models/train_full.sage")
log("  sage models/ai_builder.sage (step 3: load custom data)")
