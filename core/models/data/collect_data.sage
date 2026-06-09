gc_disable()
# Training data collection pipeline
# Collects Sage source code, documentation, tests, and C implementation
# into a single training corpus for language model training

import io
import sys

# ============================================================================
# File collection
# ============================================================================

# Read a file and return its contents with a source tag
proc read_tagged(path, tag):
    let content = io.readfile(path)
    if content == nil:
        return ""
    return "<|" + tag + "|>" + chr(10) + "# file: " + path + chr(10) + content + chr(10) + "<|end|>" + chr(10)

# Collect all .sage files from lib/ directories
proc collect_sage_libs():
    let corpus = ""
    let dirs = ["lib", "lib/graphics", "lib/os", "lib/net", "lib/crypto", "lib/ml", "lib/cuda", "lib/std", "lib/llm"]
    for d in range(len(dirs)):
        let dir_path = dirs[d]
        # Try known files in each directory
        let files = io.readfile(dir_path)
        if files != nil:
            corpus = corpus + read_tagged(dir_path, "sage_lib")
    return corpus

# Collect core Sage source (self-hosted compiler)
proc collect_sage_src():
    let corpus = ""
    let files = ["src/sage/token.sage", "src/sage/lexer.sage", "src/sage/ast.sage", "src/sage/parser.sage", "src/sage/interpreter.sage", "src/sage/compiler.sage", "src/sage/codegen.sage", "src/sage/llvm_backend.sage", "src/sage/formatter.sage", "src/sage/linter.sage", "src/sage/lsp.sage", "src/sage/module.sage", "src/sage/errors.sage", "src/sage/sage.sage", "src/sage/gc.sage", "src/sage/value.sage", "src/sage/pass.sage", "src/sage/constfold.sage", "src/sage/dce.sage", "src/sage/inline.sage"]
    for i in range(len(files)):
        let content = io.readfile(files[i])
        if content != nil:
            corpus = corpus + "<|sage_compiler|>" + chr(10) + "# file: " + files[i] + chr(10) + content + chr(10) + "<|end|>" + chr(10)
    return corpus

# Collect C implementation source
proc collect_c_src():
    let corpus = ""
    let files = ["src/c/gc.c", "src/c/interpreter.c", "src/c/parser.c", "src/c/lexer.c", "src/c/compiler.c", "src/c/value.c", "src/c/env.c", "src/c/module.c", "src/c/stdlib.c", "src/c/codegen.c", "src/c/llvm_backend.c", "src/c/ml_backend.c"]
    for i in range(len(files)):
        let content = io.readfile(files[i])
        if content != nil:
            corpus = corpus + "<|c_source|>" + chr(10) + "// file: " + files[i] + chr(10) + content + chr(10) + "<|end|>" + chr(10)
    return corpus

# Collect documentation
proc collect_docs():
    let corpus = ""
    let files = ["documentation/SageLang_Guide.md", "documentation/Import_Semantics.md", "documentation/GC_Guide.md", "documentation/Networking_Guide.md", "documentation/Cryptography_Guide.md", "documentation/ML_CUDA_Guide.md", "documentation/LLM_Guide.md", "documentation/StdLib_Guide.md", "documentation/Baremetal_OSDev_UEFI_Guide.md", "documentation/Vulkan_GPU_Guide.md"]
    for i in range(len(files)):
        let content = io.readfile(files[i])
        if content != nil:
            corpus = corpus + "<|documentation|>" + chr(10) + content + chr(10) + "<|end|>" + chr(10)
    return corpus

# Collect test files (as examples of correct Sage code + expected behavior)
proc collect_tests():
    let corpus = ""
    let test_dirs = ["tests/01_variables", "tests/03_operators", "tests/05_control", "tests/07_functions", "tests/09_arrays", "tests/11_classes", "tests/13_exceptions", "tests/16_modules"]
    # Just collect a representative sample
    return corpus

# ============================================================================
# Training example formats
# ============================================================================

# Format: instruction-following for code tasks
proc format_code_instruction(instruction, code):
    return "<|instruction|>" + chr(10) + instruction + chr(10) + "<|response|>" + chr(10) + code + chr(10) + "<|end|>" + chr(10)

# Generate synthetic instruction-following examples from the codebase
proc generate_code_examples():
    let examples = ""

    # Example: explain a function
    examples = examples + format_code_instruction("Write a Sage function that computes factorial recursively.", "proc factorial(n):" + chr(10) + "    if n <= 1:" + chr(10) + "        return 1" + chr(10) + "    return n * factorial(n - 1)")

    # Example: fix a bug
    examples = examples + format_code_instruction("Fix this Sage code that has an off-by-one error in array iteration:" + chr(10) + "for i in range(len(arr) + 1):" + chr(10) + "    print arr[i]", "# Fixed: range should be len(arr), not len(arr) + 1" + chr(10) + "for i in range(len(arr)):" + chr(10) + "    print arr[i]")

    # Example: add a new feature
    examples = examples + format_code_instruction("Add a binary search function to Sage.", "proc binary_search(arr, target):" + chr(10) + "    let lo = 0" + chr(10) + "    let hi = len(arr) - 1" + chr(10) + "    while lo <= hi:" + chr(10) + "        let mid = ((lo + hi) / 2) | 0" + chr(10) + "        if arr[mid] == target:" + chr(10) + "            return mid" + chr(10) + "        if arr[mid] < target:" + chr(10) + "            lo = mid + 1" + chr(10) + "        else:" + chr(10) + "            hi = mid - 1" + chr(10) + "    return -1")

    # Example: write a test
    examples = examples + format_code_instruction("Write a test for a stack data structure in Sage.", "gc_disable()" + chr(10) + "# EXPECT: 3" + chr(10) + "# EXPECT: 2" + chr(10) + "# EXPECT: true" + chr(10) + chr(10) + "let stack = []" + chr(10) + "push(stack, 1)" + chr(10) + "push(stack, 2)" + chr(10) + "push(stack, 3)" + chr(10) + "print len(stack)" + chr(10) + "print pop(stack)" + chr(10) + "# removed? is not needed, just check len after pop" + chr(10) + "print len(stack) == 2")

    # Example: explain Sage concepts
    examples = examples + format_code_instruction("Explain how Sage handles module imports with dotted paths.", "Sage supports dotted module paths for organized library imports. When you write:" + chr(10) + chr(10) + "    import os.fat" + chr(10) + chr(10) + "The module system converts dots to directory separators, searching:" + chr(10) + "1. ./os/fat.sage" + chr(10) + "2. ./lib/os/fat.sage" + chr(10) + "3. ./modules/os/fat.sage" + chr(10) + chr(10) + "The variable is bound using the last component, so you call fat.parse_boot_sector()." + chr(10) + "Use 'import os.fat as f' to override the binding name.")

    return examples

# ============================================================================
# Programming theory corpus
# ============================================================================

proc programming_theory():
    let corpus = ""
    corpus = corpus + "<|theory|>" + chr(10)
    corpus = corpus + "# Compiler Design Fundamentals" + chr(10)
    corpus = corpus + "A compiler translates source code through several phases:" + chr(10)
    corpus = corpus + "1. Lexical Analysis (Lexer): Converts source text into tokens" + chr(10)
    corpus = corpus + "2. Parsing: Builds an Abstract Syntax Tree (AST) from tokens" + chr(10)
    corpus = corpus + "3. Semantic Analysis: Type checking, name resolution" + chr(10)
    corpus = corpus + "4. Optimization: Constant folding, dead code elimination, inlining" + chr(10)
    corpus = corpus + "5. Code Generation: Emit target code (C, LLVM IR, assembly)" + chr(10) + chr(10)

    corpus = corpus + "# Garbage Collection Algorithms" + chr(10)
    corpus = corpus + "Mark-and-Sweep: Trace from roots, free unmarked objects." + chr(10)
    corpus = corpus + "Tri-Color Marking: White (unreached), Gray (pending), Black (scanned)." + chr(10)
    corpus = corpus + "Concurrent GC: Mark phase runs alongside mutator with write barriers." + chr(10)
    corpus = corpus + "SATB Write Barrier: Snapshot old reference before overwrite." + chr(10)
    corpus = corpus + "Generational GC: Young objects collected more frequently." + chr(10) + chr(10)

    corpus = corpus + "# Language Design Patterns" + chr(10)
    corpus = corpus + "Indentation-based scoping: Use INDENT/DEDENT tokens (Python, Sage)." + chr(10)
    corpus = corpus + "First-class functions: Functions as values, closures capture environment." + chr(10)
    corpus = corpus + "Pattern matching: Destructure values by shape (match/case)." + chr(10)
    corpus = corpus + "Algebraic data types: Tagged unions (Result, Option) for safe error handling." + chr(10)
    corpus = corpus + "Trait-based polymorphism: Behavioral contracts without inheritance." + chr(10) + chr(10)

    corpus = corpus + "# Memory Management" + chr(10)
    corpus = corpus + "Stack allocation: Local variables, function frames, automatic cleanup." + chr(10)
    corpus = corpus + "Heap allocation: Dynamic objects, managed by GC or manual free." + chr(10)
    corpus = corpus + "Reference counting: Track owners, free when count reaches zero." + chr(10)
    corpus = corpus + "Arena allocation: Bulk allocate, bulk free (no individual free)." + chr(10)
    corpus = corpus + "RAII: Resource tied to scope lifetime (constructors/destructors)." + chr(10)
    corpus = corpus + "<|end|>" + chr(10)
    return corpus

# ============================================================================
# Main collection
# ============================================================================

proc collect_all():
    print "Collecting Sage compiler source..."
    let sage_src = collect_sage_src()
    print "Collecting C implementation..."
    let c_src = collect_c_src()
    print "Collecting documentation..."
    let docs = collect_docs()
    print "Generating code examples..."
    let examples = generate_code_examples()
    print "Adding programming theory..."
    let theory = programming_theory()

    let corpus = sage_src + c_src + docs + examples + theory

    print "Total corpus length: " + str(len(corpus)) + " characters"
    print "Estimated tokens: ~" + str((len(corpus) / 4) | 0)
    return corpus

# Run collection if executed directly
let corpus = collect_all()

# Save corpus
io.writefile("models/data/corpus.txt", corpus)
print "Saved to models/data/corpus.txt"
