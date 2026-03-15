gc_disable()
# ============================================================================
# sage.sage - Self-Hosted CLI for the Sage Language
#
# Supports: interpret, emit-c, emit-llvm, emit-asm, format, lint, typecheck
# Usage: sage sage.sage [command|flags] <file.sage> [options]
# ============================================================================

import io
import sys
import pass
import compiler
import bytecode
import llvm_backend
import codegen
import formatter
import linter
import typecheck
from parser import parse_source, parse_source_file
from interpreter import new_interpreter, exec_program, set_error_context

# ============================================================================
# Constants
# ============================================================================

let NL = chr(10)
let SQ = chr(39)
let VERSION = "0.14.0"

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
    print ""
    print "Compiler flags:"
    print "  --emit-c <file>       Compile to C source"
    print "  --emit-vm <file>      Compile to VM bytecode artifact"
    print "  --emit-llvm <file>    Compile to LLVM IR"
    print "  --emit-asm <file>     Compile to assembly"
    print ""
    print "Options:"
    print "  -o <path>             Output file path"
    print "  -O0 .. -O3            Optimization level (default: 0)"
    print "  --target <arch>       Target: x86-64, aarch64, rv64 (for --emit-asm)"
    print "  --verbose             Verbose pass output"
    print "  --version             Print version"
    print "  --help                Show this help"

proc print_version():
    print "sage " + VERSION + " (self-hosted)"

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

    # No arguments beyond sage.sage
    if argc < 3:
        result["mode"] = "help"
        return result

    let i = 2
    while i < argc:
        let arg = argv[i]

        if arg == "--help":
            result["mode"] = "help"
            return result

        if arg == "--version":
            result["mode"] = "version"
            return result

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

        if arg == "--verbose":
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
# Main Dispatch
# ============================================================================

proc main():
    let args = parse_args()
    let mode = args["mode"]

    if mode == "help":
        print_usage()
        return

    if mode == "version":
        print_version()
        return

    if mode == "run":
        mode_run(args)
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
    print "Error: " + str(e)
