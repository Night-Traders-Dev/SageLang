gc_disable()
# ============================================================================
# sage.sage - Self-Hosted CLI for the Sage Language
#
# Supports: interpret, emit-c, emit-llvm, emit-asm, format, lint, typecheck
# Usage: sage sage.sage [command|flags] <file.sage> [options]
# ============================================================================

import io
import transpiler.lily.factory as lily_factory
import sys
import pass
import compiler
import bytecode
import llvm_backend
import codegen
import formatter
import linter
import typecheck
import safety
import gc
import lsp
from parser import parse_source, parse_source_file
from interpreter import new_interpreter, run_source, exec_program, set_error_context

# ============================================================================
# Constants
# ============================================================================

let NL = chr(10)
let SQ = chr(39)
let VERSION = "3"

# ============================================================================
# Usage / Help
# ============================================================================

proc print_usage():
    print "Sage Language - Self-Hosted Compiler Toolchain v" + VERSION
    print ""
    print "Usage: sage sage.sage [command] <file.sage> [options]"
    print ""
    print "Commands:"
    print "  <file.sage>           Run a Sage file (default, interpret)"
    print "  fmt <file.sage>       Format a file in-place"
    print "  lint <file.sage>      Lint a file"
    print "  check <file.sage>     Type check a file"
    print "  safety <file.sage>    Run safety analysis (ownership, borrows, lifetimes)"
    print ""
    print "Compiler flags:"
    print "  --emit-c <file>       Compile to C source"
    print "  --emit-vm <file>      Compile to VM bytecode artifact"
    print "  --emit-llvm <file>    Compile to LLVM IR"
    print "  --emit-asm <file>     Compile to assembly"
    print "  --sgvm <file>         Compile to SageVM artifact (.sgvm)"
    print "  --compile-to-lily <file>  Compile to Lily source"
    print "  --compile-from-lily <file> Compile from Lily source"
    print ""
    print "Runtime flags:"
    print "  -c <code>             Run code from a string"
    print "  --jit <file>          Run with JIT profiling (default interpreter behavior)"
    print "  --aot <file>          AOT: print type-specialized C code to stdout"
    print "  --lsp                 Start LSP server (stdin/stdout)"
    print ""
    print "Options:"
    print "  -o <path>             Output file path"
    print "  -O0 .. -O3            Optimization level (default: 0)"
    print "  --target <arch>       Target: x86-64, aarch64, rv64 (for --emit-asm)"
    print "  --check <file>        Check syntax only (no run, no typecheck)"
    print "  --strict-safety <file>  Run with strict safety enforcement"
    print "  --gc:arc|orc|tracing  Select GC mode (default: tracing)"
    print "  --repl                Start interactive REPL"
    print "  --verbose, -v         Verbose pass output"
    print "  --version             Print version"
    print "  --help                Show this help"

proc print_version():
    let info = build_info()
    let ver = info["version"]
    if ver[0] == "v":
        ver = ver[1:]
    end
    print "SageLang v" + ver
    print "Architecture : " + info["arch"]
    print "Build type   : self-hosted (host: " + info["type"] + " interpreter)"
    print "Built        : " + info["built"]
    print "Spec         : " + info["spec"]

# ============================================================================
# Argument Parsing
# ============================================================================

proc parse_args():
    let argv = sys.args()
    let argc = len(argv)
    let result = {}
    result["mode"] = "run"
    result["input"] = nil
    result["output"] = nil
    result["opt_level"] = 0
    result["target"] = "x86-64"
    result["verbose"] = false
    result["strict_safety"] = false
    result["gc_mode"] = nil

    # Argument offset: standalone runs look like
    #   [prog, sage.sage, command?, file...]  -> args start at index 2,
    # while bundled/self-extracting executables receive
    #   [exe, command?, file...]              -> args start at index 1.
    let start = 2
    if argc >= 2:
        if not endswith(argv[1], "sage.sage"):
            start = 1

    # No arguments beyond the entry point
    if argc <= start:
        result["mode"] = "help"
        return result

    let i = start
    while i < argc:
        let arg = argv[i]

        if arg == "--help":
            result["mode"] = "help"
            return result

        if arg == "--version":
            result["mode"] = "version"
            return result

        if arg == "--compile-to-lily":
            result["mode"] = "compile-to-lily"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--compile-from-lily":
            result["mode"] = "compile-from-lily"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--emit-c":
            result["mode"] = "emit-c"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--emit-vm" or arg == "--emit-bytecode":
            result["mode"] = "emit-vm"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--emit-llvm":
            result["mode"] = "emit-llvm"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--emit-asm":
            result["mode"] = "emit-asm"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--sgvm":
            result["mode"] = "emit-vm"
            result["sgvm_ext"] = true
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--emit-kotlin":
            result["mode"] = "unsupported"
            result["unsupported"] = "Kotlin backend is not available in the self-hosted build (C-only: src/c/kotlin_backend.c)"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--emit-pico-c":
            result["mode"] = "unsupported"
            result["unsupported"] = "Pico C backend is not available in the self-hosted build (C-only: src/c/pico_codegen.c)"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--compile" or arg == "--compile-native" or arg == "--compile-llvm":
            result["mode"] = "unsupported"
            result["unsupported"] = "flag requires invoking an external C/LLVM toolchain, which the self-hosted CLI cannot do (use --emit-c or --emit-llvm instead)"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--compile-jit" or arg == "--compile-pico" or arg == "--compile-bare":
            result["mode"] = "unsupported"
            result["unsupported"] = "flag requires bundling/copying the compiler executable or invoking an external toolchain; not available in the self-hosted build"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--compile-uefi" or arg == "--compile-android":
            result["mode"] = "unsupported"
            result["unsupported"] = "flag requires invoking an external SDK toolchain; not available in the self-hosted build"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--run-vm" or arg == "--run-bytecode":
            result["mode"] = "unsupported"
            result["unsupported"] = "VM bytecode execution is not available in the self-hosted build (emit artifacts with --emit-vm and run them with the sagevm binary)"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "-c":
            result["mode"] = "run-string"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--jit":
            result["mode"] = "run"
            result["jit"] = true
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--aot":
            result["mode"] = "aot"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--lsp":
            result["mode"] = "lsp"
            i = i + 1
            continue

        if arg == "fmt":
            result["mode"] = "fmt"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "lint":
            result["mode"] = "lint"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "check":
            result["mode"] = "check"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "safety":
            result["mode"] = "safety"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--check":
            result["mode"] = "syntax-check"
            i = i + 1
            if i < argc:
                result["input"] = argv[i]
            i = i + 1
            continue

        if arg == "--strict-safety":
            result["strict_safety"] = true
            i = i + 1
            continue

        if arg == "--gc:arc":
            result["gc_mode"] = "arc"
            i = i + 1
            continue

        if arg == "--gc:orc":
            result["gc_mode"] = "orc"
            i = i + 1
            continue

        if arg == "--gc:tracing":
            result["gc_mode"] = "tracing"
            i = i + 1
            continue

        if arg == "--repl":
            result["mode"] = "repl"
            i = i + 1
            continue

        if arg == "-o":
            i = i + 1
            if i < argc:
                result["output"] = argv[i]
            i = i + 1
            continue

        if arg == "-O0":
            result["opt_level"] = 0
            i = i + 1
            continue

        if arg == "-O1":
            result["opt_level"] = 1
            i = i + 1
            continue

        if arg == "-O2":
            result["opt_level"] = 2
            i = i + 1
            continue

        if arg == "-O3":
            result["opt_level"] = 3
            i = i + 1
            continue

        if arg == "--target":
            i = i + 1
            if i < argc:
                result["target"] = argv[i]
            i = i + 1
            continue

        if arg == "--verbose" or arg == "-v":
            result["verbose"] = true
            i = i + 1
            continue

        # Treat as input file if no flag matched
        if result["input"] == nil:
            result["input"] = arg

        i = i + 1

    return result

# ============================================================================
# Utilities
# ============================================================================

proc derive_output(input_path, suffix):
    let dot = -1
    let i = len(input_path) - 1
    while i >= 0:
        if input_path[i] == ".":
            dot = i
            break
        i = i - 1
    if dot >= 0:
        return slice(input_path, 0, dot) + suffix
    return input_path + suffix

proc read_input(path):
    let source = io.readfile(path)
    if source == nil:
        print "Error: Could not read file " + SQ + path + SQ
        return nil
    return source

proc resolve_target(name):
    if name == "x86-64":
        return codegen.TARGET_X86_64
    if name == "x86_64":
        return codegen.TARGET_X86_64
    if name == "aarch64":
        return codegen.TARGET_AARCH64
    if name == "arm64":
        return codegen.TARGET_AARCH64
    if name == "rv64":
        return codegen.TARGET_RV64
    if name == "riscv64":
        return codegen.TARGET_RV64
    print "Error: Unknown target " + SQ + name + SQ
    print "Supported targets: x86-64, aarch64, rv64"
    return nil

proc make_pass_ctx(args):
    let ctx = {}
    ctx["opt_level"] = args["opt_level"]
    ctx["verbose"] = args["verbose"]
    ctx["debug_info"] = false
    return ctx

# ============================================================================
# Mode: Run (Interpret)
# ============================================================================

proc mode_run(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    if args["strict_safety"]:
        if run_strict_safety(path) == false:
            return
    let source = read_input(path)
    if source == nil:
        return
    let stmts = parse_source_file(source, path)
    if args["opt_level"] > 0:
        let ctx = make_pass_ctx(args)
        stmts = pass.run_passes(stmts, ctx)
    set_error_context(source, path)
    let genv = new_interpreter()
    exec_program(genv, stmts)

# ============================================================================
# Mode: Emit C
# ============================================================================

proc mode_emit_c(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    let stmts = parse_source_file(source, path)
    if args["opt_level"] > 0:
        let ctx = make_pass_ctx(args)
        stmts = pass.run_passes(stmts, ctx)
    let c_source = compiler.compile_to_c(stmts)
    if c_source == "":
        print "Error: Compilation to C failed"
        return
    let out = args["output"]
    if out == nil:
        out = derive_output(path, ".c")
    io.writefile(out, c_source)
    print "Wrote " + out

# ============================================================================
# Mode: Emit VM Artifact
# ============================================================================

proc mode_emit_vm(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    let stmts = parse_source_file(source, path)
    if args["opt_level"] > 0:
        let ctx = make_pass_ctx(args)
        stmts = pass.run_passes(stmts, ctx)
    let artifact = bytecode.compile_to_vm_artifact(stmts)
    if artifact == nil:
        print "Error: VM compilation failed: " + bytecode.get_error()
        return
    let out = args["output"]
    if out == nil:
        if dict_has(args, "sgvm_ext") and args["sgvm_ext"]:
            out = derive_output(path, ".sgvm")
        else:
            out = derive_output(path, ".svm")
    io.writefile(out, artifact)
    print "Wrote " + out

# ============================================================================
# Mode: Emit LLVM IR
# ============================================================================

proc mode_emit_llvm(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    let stmts = parse_source_file(source, path)
    if args["opt_level"] > 0:
        let ctx = make_pass_ctx(args)
        stmts = pass.run_passes(stmts, ctx)
    let ir = llvm_backend.compile_to_llvm_ir(stmts)
    let out = args["output"]
    if out == nil:
        out = derive_output(path, ".ll")
    io.writefile(out, ir)
    print "Wrote " + out

# ============================================================================
# Mode: Emit Assembly
# ============================================================================

proc mode_emit_asm(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    let target = resolve_target(args["target"])
    if target == nil:
        return
    let stmts = parse_source_file(source, path)
    if args["opt_level"] > 0:
        let ctx = make_pass_ctx(args)
        stmts = pass.run_passes(stmts, ctx)
    let asm = codegen.compile_to_asm(stmts, target)
    let out = args["output"]
    if out == nil:
        out = derive_output(path, ".s")
    io.writefile(out, asm)
    print "Wrote " + out

# ============================================================================
# Mode: Run String (-c)
# ============================================================================

proc mode_run_string(args):
    let source = args["input"]
    if source == nil:
        print "Error: -c requires a source string"
        return
    let stmts = parse_source(source)
    if args["opt_level"] > 0:
        let ctx = make_pass_ctx(args)
        stmts = pass.run_passes(stmts, ctx)
    set_error_context(source, "<command>")
    let genv = new_interpreter()
    exec_program(genv, stmts)

# ============================================================================
# Mode: AOT (--aot)
# C behavior: without -o, print type-specialized C code to stdout;
# with -o, write <out>.c (the cc invocation step cannot run self-hosted).
# ============================================================================

proc mode_aot(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    let stmts = parse_source_file(source, path)
    let ctx = make_pass_ctx(args)
    ctx["opt_level"] = 2
    stmts = pass.run_passes(stmts, ctx)
    let c_code = compiler.compile_to_c(stmts)
    let out = args["output"]
    if out == nil:
        print c_code
        return
    io.writefile(out + ".c", c_code)
    print "Wrote " + out + ".c"
    print "Note: linking a native binary requires an external C toolchain (not available in the self-hosted build)"

# ============================================================================
# Mode: Unsupported flag
# ============================================================================

proc mode_unsupported(args):
    print "Error: " + args["unsupported"]

# ============================================================================
# Mode: Format
# ============================================================================

proc mode_fmt(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    let formatted = formatter.format_source(source)
    io.writefile(path, formatted)
    print "Formatted " + path

# ============================================================================
# Mode: Lint
# ============================================================================

proc mode_lint(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    let messages = linter.lint_source(source)
    let count = len(messages)
    for msg in messages:
        let line = path + ":" + str(msg["line"]) + ":" + str(msg["col"])
        let sev = msg["severity"]
        let rule = msg["rule"]
        let text = msg["message"]
        print line + ": " + sev + ": [" + rule + "] " + text
    if count == 0:
        print "No lint issues found in " + path
    if count > 0:
        print str(count) + " issue(s) found"

# ============================================================================
# Mode: Type Check
# ============================================================================

proc mode_check(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    let stmts = parse_source_file(source, path)
    let ctx = make_pass_ctx(args)
    typecheck.pass_typecheck(stmts, ctx)
    print "Type check complete: " + path

# ============================================================================
# Mode: Syntax Check
# ============================================================================

proc mode_syntax_check(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    parse_source_file(source, path)
    print "Syntax OK: " + path

# ============================================================================
# Mode: Safety Analysis
# ============================================================================

proc mode_safety(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    let stmts = parse_source_file(source, path)
    let result = safety.analyze(stmts, safety.MODE_STRICT, path)
    if result["ok"] == false:
        raise "Safety analysis failed: " + str(result["error_count"]) + " error(s)"
    print "Safety analysis complete: no issues found."

proc run_strict_safety(path):
    let source = read_input(path)
    if source == nil:
        return false
    let stmts = parse_source_file(source, path)
    let result = safety.analyze(stmts, safety.MODE_STRICT, path)
    if result["ok"] == false:
        raise "Strict safety check failed: " + str(result["error_count"]) + " error(s)"
    return true

# ============================================================================
# Mode: REPL
# ============================================================================

proc mode_repl(args):
    print "Sage " + VERSION + " (self-hosted) - interactive REPL"
    print "Type Sage statements. Blank line executes. Type 'exit' or 'quit' to leave."
    let buffer = ""
    let prompt = "sage> "
    let genv = new_interpreter()
    while true:
        print prompt
        let line = input()
        if line == nil:
            print ""
            break
        if line == "exit" or line == "quit":
            break
        if line == "":
            if buffer != "":
                let source = buffer
                buffer = ""
                set_error_context(source, "<repl>")
                run_source(genv, source)
            continue
        if len(buffer) > 0:
            buffer = buffer + chr(10) + line
        else:
            buffer = line

# ============================================================================
# Mode: Lily Transpilation
# ============================================================================

proc mode_compile_to_lily(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    let t = lily_factory.get_parser("sage_to_lily")
    let lily_code = t.transpile(source)
    if lily_code == nil or lily_code == "":
        print "Error: Transpilation to Lily failed"
        return
    let out = args["output"]
    if out == nil:
        out = derive_output(path, ".lily")
    io.writefile(out, lily_code)
    print "Wrote " + out

proc mode_compile_from_lily(args):
    let path = args["input"]
    if path == nil:
        print "Error: No input file specified"
        return
    let source = read_input(path)
    if source == nil:
        return
    let t = lily_factory.get_parser("lily_to_sage")
    let sage_code = t.transpile(source)
    if sage_code == nil or sage_code == "":
        print "Error: Transpilation from Lily failed"
        return
    let out = args["output"]
    if out == nil:
        out = derive_output(path, ".sage")
    io.writefile(out, sage_code)
    print "Wrote " + out

# ============================================================================
# Main Dispatch
# ============================================================================

proc main():
    let args = parse_args()
    let mode = args["mode"]

    if args["gc_mode"] != nil:
        let gc_mode = args["gc_mode"]
        gc.controller.set_mode(gc_mode)

    if mode == "help":
        print_usage()
        return

    if mode == "version":
        print_version()
        return

    if mode == "run":
        mode_run(args)
        return

    if mode == "run-string":
        mode_run_string(args)
        return

    if mode == "aot":
        mode_aot(args)
        return

    if mode == "lsp":
        lsp.lsp_run()
        return

    if mode == "unsupported":
        mode_unsupported(args)
        return

    if mode == "syntax-check":
        mode_syntax_check(args)
        return

    if mode == "safety":
        mode_safety(args)
        return

    if mode == "repl":
        mode_repl(args)
        return

    if mode == "compile-to-lily":
        mode_compile_to_lily(args)
        return

    if mode == "compile-from-lily":
        mode_compile_from_lily(args)
        return

    if mode == "emit-c":
        mode_emit_c(args)
        return

    if mode == "emit-vm":
        mode_emit_vm(args)
        return

    if mode == "emit-llvm":
        mode_emit_llvm(args)
        return

    if mode == "emit-asm":
        mode_emit_asm(args)
        return

    if mode == "fmt":
        mode_fmt(args)
        return

    if mode == "lint":
        mode_lint(args)
        return

    if mode == "check":
        mode_check(args)
        return

    print "Error: Unknown mode " + SQ + mode + SQ
    print_usage()

try:
    main()
catch e:
    # Formatted diagnostics (parser errors) already carry their own
    # lowercase severity; only plain exceptions get the wrapper.
    let msg = str(e)
    if len(msg) >= 6 and msg[0:6] == "error:":
        print msg
    else:
        print "Error: " + msg
