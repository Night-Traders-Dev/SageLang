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
from interpreter import new_interpreter, run_source, exec_program, exec_program_dynamic, set_error_context
from interpreter import eval_expr, value_to_string, interpreter_call_depth, module_cache_names, module_search_paths
from ast import STMT_EXPRESSION, EXPR_SET, EXPR_INDEX_SET

# ============================================================================
# Constants
# ============================================================================

let NL = chr(10)
let SQ = chr(39)
let VERSION = "4.2.10"

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

    # No arguments beyond the entry point: start the interactive REPL
    # (mirrors the C host, which also drops into its REPL on bare invocation)
    if argc <= start:
        result["mode"] = "repl"
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

# Heuristic: is this chunk an executable unit?
# True when no string/bracket is left open and the last significant
# character is not ':' (a block opener awaiting an indented body).
proc repl_chunk_complete(src):
    let n = len(src)
    let paren = 0
    let bracket = 0
    let brace = 0
    let in_str = false
    let quote_ch = ""
    let last_sig = ""
    let i = 0
    while i < n:
        let c = src[i]
        if in_str:
            if c == "\\":
                i = i + 2
                continue
            if c == quote_ch:
                in_str = false
            i = i + 1
            continue
        if c == "\"" or c == "'":
            in_str = true
            quote_ch = c
        else:
            if c == "#":
                break
            if c == "(":
                paren = paren + 1
            elif c == ")":
                paren = paren - 1
            elif c == "[":
                bracket = bracket + 1
            elif c == "]":
                bracket = bracket - 1
            elif c == "{":
                brace = brace + 1
            elif c == "}":
                brace = brace - 1
            elif c != " " and c != chr(9):
                last_sig = c
        i = i + 1
    if in_str:
        return false
    if paren < 0 or bracket < 0 or brace < 0:
        return true
    if paren != 0 or bracket != 0 or brace != 0:
        return false
    if last_sig == ":":
        return false
    return true

proc repl_starts_block(line):
    let text = strip(line)
    if len(text) == 0:
        return false
    return text[len(text) - 1] == ":"

proc repl_command_arg(line, command):
    let command_len = len(command)
    if len(line) < command_len:
        return nil
    if slice(line, 0, command_len) != command:
        return nil
    if len(line) == command_len:
        return ""
    if line[command_len] != " " and line[command_len] != chr(9):
        return nil
    var start = command_len
    while start < len(line):
        if line[start] != " " and line[start] != chr(9):
            break
        start = start + 1
    return slice(line, start, len(line))

proc repl_stat(stats, key, fallback):
    if dict_has(stats, key):
        return stats[key]
    return fallback

proc repl_repr(value):
    if type(value) == "string":
        return "\"" + value + "\""
    return value_to_string(value)

proc repl_print_error(error):
    let message = str(error)
    if startswith(message, "error:"):
        print message
    else:
        print "Error: " + message

proc repl_print_help():
    print "Sage REPL Commands:"
    print ""
    print "  Session:"
    print "    :help              Show this help message"
    print "    :quit / :exit      Exit the REPL (also Ctrl-D)"
    print "    :reset             Reset session globals"
    print "    :clear             Clear the screen"
    print "    :history [n]       Show last n entries (default: 20)"
    print "    :search <pattern>  Search history for a pattern"
    print "    :clear-history     Clear session history"
    print "    :save <file>       Save session history to a Sage file"
    print "    :edit [file]       Edit a file (or a temporary buffer) and execute it"
    print ""
    print "  Inspection:"
    print "    :vars [prefix]     List bindings, optionally filtered by prefix"
    print "    :type <expr>       Evaluate expression and show its type"
    print "    :doc <name>        Show documentation for a function or keyword"
    print "    :ast <code>        Show parsed AST for an expression or statement"
    print "    :env               Show the full scope chain"
    print "    :modules           List loaded modules and search paths"
    print ""
    print "  Compilation:"
    print "    :emit-c <code>     Show C backend output for a statement"
    print "    :emit-llvm <code>  Show LLVM IR output for a statement"
    print "    :emit-kotlin <code> Show Kotlin backend output for a statement"
    print ""
    print "  Performance:"
    print "    :time <expr>       Time a single expression evaluation"
    print "    :bench <n> <expr>  Run expression n times and show stats"
    print ""
    print "  System:"
    print "    :pwd               Print the current working directory"
    print "    :cd <dir>          Change the current working directory"
    print "    :ls [dir]          List files in a directory"
    print "    :cat <file>        Print the contents of a file"
    print "    :sh <command>      Execute a shell command"
    print "    :gc                Run garbage collection and print stats"
    print "    :stats             Print interpreter and GC statistics"
    print "    :runtime [mode]    Show or set the self-hosted runtime"
    print "    :version           Show version, architecture, and build type"
    print ""
    print "Multi-line blocks are detected when a line ends with ':'."
    print "End a block with an empty line."

proc repl_print_stats():
    let stats = gc_stats()
    if stats == nil:
        print "GC statistics are unavailable."
        return
    let mode = repl_stat(stats, "mode", "tracing")
    let mode_label = "Tracing"
    if mode == "arc":
        mode_label = "ARC"
    elif mode == "orc":
        mode_label = "ORC"
    print "=== GC Statistics (" + mode_label + " mode) ==="
    print "Collections run:        " + str(repl_stat(stats, "collections", 0))
    print "Objects allocated:      " + str(repl_stat(stats, "num_objects", 0))
    print "Objects since GC:       " + str(repl_stat(stats, "objects_since_gc", 0))
    print "Total bytes allocated:  " + str(repl_stat(stats, "bytes_allocated", 0))
    print "Total bytes freed:      " + str(repl_stat(stats, "bytes_freed", 0))
    print "Current memory usage:   " + str(repl_stat(stats, "current_bytes", 0)) + " bytes"
    print "Marked in last cycle:   " + str(repl_stat(stats, "marked_count", 0))
    print "Freed in last cycle:    " + str(repl_stat(stats, "freed_count", 0))
    print "Max STW pause:          " + str(repl_stat(stats, "max_pause_us", 0)) + " us"
    print "Last root scan:         " + str(repl_stat(stats, "last_root_scan_us", 0)) + " us"
    print "Last remark:            " + str(repl_stat(stats, "last_remark_us", 0)) + " us"
    print "Last sweep:             " + str(repl_stat(stats, "last_sweep_us", 0)) + " us"
    print "Current phase:          " + str(repl_stat(stats, "phase", 0))
    let barrier = repl_stat(stats, "barrier_active", false)
    if barrier:
        print "Write barrier active:   yes"
    else:
        print "Write barrier active:   no"
    let enabled = repl_stat(stats, "enabled", false)
    if enabled:
        print "GC enabled:             yes"
    else:
        print "GC enabled:             no"
    print "Interpreter Stack Depth: " + str(interpreter_call_depth())
    print "Process CPU Time:        " + str(repl_cpu_time()) + " seconds"
    print "================================"

proc repl_print_gc_stats():
    gc_collect()
    repl_print_stats()

proc repl_print_bindings(genv, prefix):
    if prefix == nil:
        prefix = ""
    let values = genv["vals"]
    let names = dict_keys(values)
    let shown = 0
    for name in names:
        if prefix == "" or startswith(name, prefix):
            print name + " = " + repl_repr(values[name])
            shown = shown + 1
    if shown == 0:
        if prefix != "":
            print "No bindings match prefix \"" + prefix + "\"."
        else:
            print "No bindings in the current REPL scope."
    else:
        if shown == 1:
            print "1 binding shown."
        else:
            print str(shown) + " bindings shown."

proc repl_print_env(genv):
    let current = genv
    let level = 0
    while current != nil:
        let names = dict_keys(current["vals"])
        print "Scope " + str(level) + ": " + str(len(names)) + " bindings"
        current = current["parent"]
        level = level + 1

proc repl_eval_expression(genv, source):
    set_error_context(source, "<repl>")
    let stmts = parse_source_file(source, "<repl>")
    if len(stmts) != 1 or stmts[0].type != STMT_EXPRESSION:
        raise "Expression did not produce a value."
    let expr = stmts[0].expression
    if expr.type == EXPR_SET or expr.type == EXPR_INDEX_SET:
        raise "Expression did not produce a value."
    return eval_expr(expr, genv)

proc repl_run_chunk(genv, source):
    set_error_context(source, "<repl>")
    try:
        let stmts = parse_source_file(source, "<repl>")
        let index = 0
        while index < len(stmts):
            let stmt = stmts[index]
            if stmt.type == STMT_EXPRESSION:
                let expr = stmt.expression
                let value = eval_expr(expr, genv)
                if value != nil:
                    print repl_repr(value)
            else:
                let one = [stmt]
                if genv["repl_runtime_mode"] == "ast":
                    exec_program_dynamic(genv, one)
                else:
                    exec_program(genv, one)
            index = index + 1
        return nil
    catch e:
        repl_print_error(e)

proc repl_handle_command(line, genv, history):
    if line == ":quit" or line == ":exit" or line == ":q":
        return 2
    if line == "version":
        print_version()
        return 1

    var arg = repl_command_arg(line, ":help")
    if arg != nil:
        repl_print_help()
        return 1

    arg = repl_command_arg(line, ":stats")
    if arg != nil:
        repl_print_stats()
        return 1

    arg = repl_command_arg(line, ":gc")
    if arg != nil:
        repl_print_gc_stats()
        return 1

    arg = repl_command_arg(line, ":version")
    if arg != nil:
        print_version()
        return 1

    arg = repl_command_arg(line, ":reset")
    if arg != nil:
        let fresh = new_interpreter()
        genv["vals"] = fresh["vals"]
        genv["parent"] = fresh["parent"]
        print "REPL session reset."
        return 1

    arg = repl_command_arg(line, ":pwd")
    if arg != nil:
        print(repl_getcwd())
        return 1

    arg = repl_command_arg(line, ":cd")
    if arg != nil:
        if arg == "":
            print "Usage: :cd <dir>"
        elif repl_chdir(arg):
            print(repl_getcwd())
        else:
            print "chdir: unable to change directory"
        return 1

    arg = repl_command_arg(line, ":ls")
    if arg != nil:
        var directory = arg
        if directory == "":
            directory = "."
        let entries = io.listdir(directory)
        if entries == nil:
            print "ls: unable to read directory " + directory
        else:
            for entry in entries:
                print entry
        return 1

    arg = repl_command_arg(line, ":cat")
    if arg != nil:
        if arg == "":
            print "Usage: :cat <file>"
        else:
            let content = io.readfile(arg)
            if content == nil:
                print "cat: unable to read " + arg
            else:
                print content
        return 1

    arg = repl_command_arg(line, ":sh")
    if arg != nil:
        if arg == "":
            print "Usage: :sh <command>"
        else:
            let status = repl_exec(arg)
            if status < 0:
                print "Security Error: Unsafe characters in command"
        return 1

    arg = repl_command_arg(line, ":vars")
    if arg != nil:
        repl_print_bindings(genv, arg)
        return 1

    arg = repl_command_arg(line, ":type")
    if arg != nil:
        if arg == "":
            print "Usage: :type <expr>"
        else:
            let value = repl_eval_expression(genv, arg)
            print type(value) + " = " + repl_repr(value)
        return 1

    arg = repl_command_arg(line, ":doc")
    if arg != nil:
        if arg == "":
            print "Usage: :doc <name>"
        elif arg == "gc":
            print "Garbage collection controls and statistics."
        elif arg == "import":
            print "Load a Sage module from the configured module search paths."
        else:
            print "No documentation found for \"" + arg + "\"."
        return 1

    arg = repl_command_arg(line, ":clear")
    if arg != nil:
        print "\x1b[2J\x1b[H"
        return 1

    arg = repl_command_arg(line, ":history")
    if arg != nil:
        var count = 20
        if arg != "":
            count = tonumber(arg)
            if count <= 0:
                count = 20
        var start = len(history) - count
        if start < 0:
            start = 0
        var index = start
        while index < len(history):
            print "  " + str(index + 1) + "  " + history[index]
            index = index + 1
        if len(history) == 0:
            print "No history."
        return 1

    arg = repl_command_arg(line, ":search")
    if arg != nil:
        if arg == "":
            print "Usage: :search <pattern>"
        else:
            var matches = 0
            var index = 0
            while index < len(history):
                if contains(history[index], arg):
                    print "  " + str(index + 1) + "  " + history[index]
                    matches = matches + 1
                index = index + 1
            if matches == 0:
                print "No matches found for \"" + arg + "\"."
            else:
                print str(matches) + " matches found."
        return 1

    arg = repl_command_arg(line, ":clear-history")
    if arg != nil:
        while len(history) > 0:
            pop(history)
        print "History cleared."
        return 1

    arg = repl_command_arg(line, ":save")
    if arg != nil:
        if arg == "":
            print "Usage: :save <file>"
        else:
            var content = ""
            for entry in history:
                if len(entry) > 0 and entry[0] != ":":
                    if content != "":
                        content = content + chr(10)
                    content = content + entry
            io.writefile(arg, content)
            print "Saved session history to " + arg
        return 1

    arg = repl_command_arg(line, ":edit")
    if arg != nil:
        if arg == "":
            let editor = repl_getenv("EDITOR")
            if editor == nil:
                editor = repl_getenv("VISUAL")
            if editor == nil:
                editor = "vi"
            arg = "/tmp/sage_repl_edit_" + str(clock()) + ".sage"
            io.writefile(arg, "")
        let editor = repl_getenv("EDITOR")
        if editor == nil:
            editor = repl_getenv("VISUAL")
        if editor == nil:
            editor = "vi"
        if contains(arg, "'") or contains(editor, "'"):
            print "Security Error: Unsafe characters in editor path"
            return 1
        let status = repl_exec(editor + " '" + arg + "'")
        if status != 0:
            print "Editor exited with status " + str(status)
        else:
            let source = io.readfile(arg)
            if source != nil:
                repl_run_chunk(genv, source)
            if startswith(arg, "/tmp/sage_repl_edit_"):
                io.remove(arg)
        return 1

    arg = repl_command_arg(line, ":env")
    if arg != nil:
        repl_print_env(genv)
        return 1

    arg = repl_command_arg(line, ":modules")
    if arg != nil:
        let names = module_cache_names()
        if len(names) == 0:
            print "No modules loaded."
        else:
            for name in names:
                print "  " + name
            if len(names) == 1:
                print "1 module in cache."
            else:
                print str(len(names)) + " modules in cache."
        let paths = module_search_paths()
        if len(paths) > 0:
            print "Search paths:"
            for path in paths:
                print "  " + path
        return 1

    arg = repl_command_arg(line, ":load")
    if arg != nil:
        if arg == "":
            print "Usage: :load <file>"
        else:
            let source = io.readfile(arg)
            if source == nil:
                print "sage repl: could not open \"" + arg + "\""
            else:
                repl_run_chunk(genv, source)
        return 1

    arg = repl_command_arg(line, ":ast")
    if arg != nil:
        if arg == "":
            print "Usage: :ast <code>"
        else:
            let stmts = parse_source_file(arg, "<repl-ast>")
            var index = 0
            while index < len(stmts):
                print value_to_string(stmts[index])
                index = index + 1
        return 1

    arg = repl_command_arg(line, ":emit-c")
    if arg != nil:
        if arg == "":
            print "Usage: :emit-c <code>"
        else:
            let stmts = parse_source_file(arg, "<repl>")
            print compiler.compile_to_c(stmts)
        return 1

    arg = repl_command_arg(line, ":emit-llvm")
    if arg != nil:
        if arg == "":
            print "Usage: :emit-llvm <code>"
        else:
            let stmts = parse_source_file(arg, "<repl>")
            print llvm_backend.compile_to_llvm_ir(stmts)
        return 1

    arg = repl_command_arg(line, ":emit-kotlin")
    if arg != nil:
        if arg == "":
            print "Usage: :emit-kotlin <code>"
        else:
            print "Kotlin backend output is unavailable in the self-hosted REPL."
        return 1

    arg = repl_command_arg(line, ":time")
    if arg != nil:
        if arg == "":
            print "Usage: :time <expr>"
        else:
            let started = clock()
            let value = repl_eval_expression(genv, arg)
            let elapsed = clock() - started
            if value != nil:
                print repl_repr(value)
            print "  " + str(elapsed * 1000000) + " us"
        return 1

    arg = repl_command_arg(line, ":bench")
    if arg != nil:
        let parts = split(strip(arg), " ")
        if len(parts) < 2:
            print "Usage: :bench <n> <expr>"
        else:
            var count = tonumber(parts[0])
            if count <= 0:
                print "Usage: :bench <n> <expr>"
            else:
                if count > 1000000:
                    count = 1000000
                var expression = ""
                var part_index = 1
                while part_index < len(parts):
                    if expression != "":
                        expression = expression + " "
                    expression = expression + parts[part_index]
                    part_index = part_index + 1
                var total = 0
                var minimum = 1000000000
                var maximum = 0
                var iteration = 0
                while iteration < count:
                    let started = clock()
                    repl_eval_expression(genv, expression)
                    let elapsed = clock() - started
                    total = total + elapsed
                    if elapsed < minimum:
                        minimum = elapsed
                    if elapsed > maximum:
                        maximum = elapsed
                    iteration = iteration + 1
                let average = total / count
                print str(count) + " iterations: total=" + str(total) + "s, avg=" + str(average) + "s, min=" + str(minimum) + "s, max=" + str(maximum) + "s"
        return 1

    arg = repl_command_arg(line, ":runtime")
    if arg != nil:
        if arg == "":
            print "Current runtime: " + genv["repl_runtime_mode"]
        elif arg == "ast" or arg == "bytecode" or arg == "jit" or arg == "aot" or arg == "auto" or arg == "self-hosted":
            if arg == "ast":
                genv["repl_runtime_mode"] = "ast"
            else:
                genv["repl_runtime_mode"] = "self-hosted"
            print "Runtime set to: " + genv["repl_runtime_mode"]
        else:
            print "Unknown runtime mode: " + arg + " (use ast, bytecode, jit, aot, or auto)"
        return 1

    return 0

proc mode_repl(args):
    print "Sage " + VERSION + " (self-hosted) - interactive REPL"
    print "Complete statements run immediately. End a line with ':' to open a block; a blank line executes it. Type 'help' for commands or 'exit' to leave."
    gc_enable()
    let genv = new_interpreter()
    genv["repl_runtime_mode"] = "self-hosted"
    let history = []
    var buffer = ""
    var block_mode = false
    while true:
        if len(buffer) > 0:
            print "... "
        else:
            print "sage> "
        let line = input()
        if line == nil:
            if buffer != "":
                repl_run_chunk(genv, buffer)
            print ""
            break
        let trimmed = strip(line)
        if trimmed != "":
            push(history, line)
        if buffer == "" and (trimmed == "exit" or trimmed == "quit" or trimmed == ":exit" or trimmed == ":quit" or trimmed == ":q"):
            break
        if buffer == "" and ((len(trimmed) > 0 and trimmed[0] == ":") or trimmed == "version"):
            var action = 0
            try:
                action = repl_handle_command(trimmed, genv, history)
            catch e:
                repl_print_error(e)
            if action == 2:
                break
            if action == 1:
                continue
            print "Unknown REPL command: " + trimmed
            print "Type :help for available commands."
            continue
        if trimmed == "":
            if buffer != "":
                let source = buffer
                buffer = ""
                block_mode = false
                repl_run_chunk(genv, source)
            continue
        if len(buffer) > 0:
            buffer = buffer + chr(10) + line
        else:
            buffer = line
            block_mode = repl_starts_block(line)
        if block_mode == false and repl_chunk_complete(buffer):
            let source = buffer
            buffer = ""
            block_mode = false
            repl_run_chunk(genv, source)

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
        if gc_mode == "arc":
            gc_set_arc()
        elif gc_mode == "orc":
            gc_set_orc()
        else:
            gc_set_tracing()

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
