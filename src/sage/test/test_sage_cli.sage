gc_disable()
# Tests for the self-hosted sage.sage CLI utilities
# Tests: derive_output, parse_source_file, compilation pipelines

let nl = chr(10)
let passed = 0
let failed = 0

proc assert_eq(actual, expected, msg):
    if actual == expected:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg
        print "  expected: " + str(expected)
        print "  actual:   " + str(actual)

proc assert_contains(haystack, needle, msg):
    if contains(haystack, needle):
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (should contain: " + needle + ")"

print "Self-hosted Sage CLI Tests"
print "=========================="

# ============================================================================
# Test derive_output (replicated logic - sage.sage runs main() on import)
# ============================================================================

print nl + "--- derive_output ---"

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

assert_eq(derive_output("hello.sage", ".c"), "hello.c", "derive .sage -> .c")
assert_eq(derive_output("hello.sage", ".ll"), "hello.ll", "derive .sage -> .ll")
assert_eq(derive_output("hello.sage", ".s"), "hello.s", "derive .sage -> .s")
assert_eq(derive_output("hello.sage", ""), "hello", "derive .sage -> no ext")
assert_eq(derive_output("path/to/file.sage", ".c"), "path/to/file.c", "derive with path")
assert_eq(derive_output("noext", ".c"), "noext.c", "derive no extension")
assert_eq(derive_output("multi.dot.sage", ".c"), "multi.dot.c", "derive multiple dots")

# ============================================================================
# Test parse_source_file (rich error messages)
# ============================================================================

print nl + "--- parse_source_file ---"

from parser import parse_source_file, parse_source

let simple_src = "let x = 42" + nl + "print x"
let stmts = parse_source_file(simple_src, "test_input.sage")
assert_eq(type(stmts), "array", "parse returns array")
assert_eq(len(stmts), 2, "parse returns 2 stmts")

# Test that parse errors include filename in rich format
let bad_src = "let = "
let got_error = false
let error_msg = ""
try:
    parse_source_file(bad_src, "bad_file.sage")
catch e:
    got_error = true
    error_msg = str(e)

assert_eq(got_error, true, "parse error raised")
assert_contains(error_msg, "bad_file.sage", "error contains filename")
assert_contains(error_msg, "Error:", "error has Error: prefix")

# Test error with hints
let bad_src2 = "if:" + nl + "    print 1"
let got_error2 = false
let error_msg2 = ""
try:
    parse_source_file(bad_src2, "hint_test.sage")
catch e:
    got_error2 = true
    error_msg2 = str(e)

assert_eq(got_error2, true, "hint error raised")
assert_contains(error_msg2, "hint_test.sage", "hint error has filename")
assert_contains(error_msg2, "hint:", "error has hint")

# ============================================================================
# Test compilation to C
# ============================================================================

print nl + "--- compile_to_c pipeline ---"

import compiler
import bytecode

let c_src = "print 42"
let c_stmts = parse_source(c_src)
let c_output = compiler.compile_to_c(c_stmts)
assert_contains(c_output, "sage_print", "C output has sage_print")
assert_contains(c_output, "int main", "C output has main")

# ============================================================================
# Test compilation to VM artifact
# ============================================================================

print nl + "--- compile_to_vm_artifact pipeline ---"

let vm_src = "let x = 10" + nl + "print x"
let vm_stmts = parse_source(vm_src)
let vm_output = bytecode.compile_to_vm_artifact(vm_stmts)
assert_contains(vm_output, "SAGEBC1", "VM artifact has header")
assert_contains(vm_output, "chunks 2", "VM artifact has chunk count")

# ============================================================================
# Test compilation to LLVM IR
# ============================================================================

print nl + "--- compile_to_llvm_ir pipeline ---"

import llvm_backend

let ll_src = "let x = 10" + nl + "print x"
let ll_stmts = parse_source(ll_src)
let ll_output = llvm_backend.compile_to_llvm_ir(ll_stmts)
assert_contains(ll_output, "define", "LLVM IR has define")
assert_contains(ll_output, "@main", "LLVM IR has @main")

# ============================================================================
# Test compilation to assembly
# ============================================================================

print nl + "--- compile_to_asm pipeline ---"

import codegen

let asm_src = "print 1"
let asm_stmts = parse_source(asm_src)
let asm_output = codegen.compile_to_asm(asm_stmts, codegen.TARGET_X86_64)
assert_contains(asm_output, ".text", "ASM has .text")
assert_contains(asm_output, "main", "ASM has main")

# ============================================================================
# Test optimization passes
# ============================================================================

print nl + "--- optimization passes ---"

import pass

let opt_src = "let x = 2 + 3" + nl + "print x"
let opt_stmts = parse_source(opt_src)
let opt_ctx = {}
opt_ctx["opt_level"] = 1
opt_ctx["verbose"] = false
opt_ctx["debug_info"] = false
let optimized = pass.run_passes(opt_stmts, opt_ctx)
assert_eq(type(optimized), "array", "optimized is array")

# Constant folding at -O1 then compile
let fold_stmts = parse_source(opt_src)
let fold_ctx = {}
fold_ctx["opt_level"] = 1
fold_ctx["verbose"] = false
fold_ctx["debug_info"] = false
let folded = pass.run_passes(fold_stmts, fold_ctx)
let folded_c = compiler.compile_to_c(folded)
assert_contains(folded_c, "int main", "folded compiles to C")

# ============================================================================
# Test formatter integration
# ============================================================================

print nl + "--- formatter ---"

import formatter

let fmt_src = "let   x=1" + nl + "let y =  2"
let formatted = formatter.format_source(fmt_src)
assert_contains(formatted, "let", "formatted has let")

# ============================================================================
# Test linter integration
# ============================================================================

print nl + "--- linter ---"

import linter

let lint_src = "proc badName():" + nl + "    print 42"
let lint_msgs = linter.lint_source(lint_src)
assert_eq(type(lint_msgs), "array", "lint returns array")

# ============================================================================
# Summary
# ============================================================================

print nl + "Sage CLI Tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All Sage CLI tests passed!"
else:
    print "SOME TESTS FAILED"
