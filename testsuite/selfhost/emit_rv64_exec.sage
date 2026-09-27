#########################################################################
## SageLang -- emit rv64 assembly from the self-hosting codegen for execution
##
## The instruction-level assertions in test_codegen.sage all passed while the
## emitted program segfaulted. Reading the assembly cannot reveal that the rv64
## prologue saved ra and s0 at 8(sp) and 0(sp), which are vreg 0 and vreg 1, so
## the first two virtual registers were clobbered before any instruction ran;
## that both halves of an operand were read from the same offset; or that
## sage_globals was materialised from %hi alone with no %lo addend. None of that
## shows up in the instruction text, so it takes building and running the output.
##
## The Makefile target compiles and runs what this writes, and diffs against
## compiler_asm_ops.expected, which is the C backend's output for the same
## values. So the native path is checked against an independent implementation
## rather than against itself.
##
## Run from core/src/sage:  ../../sage ../../../testsuite/selfhost/emit_rv64_exec.sage
#########################################################################

import ast
import io
import token
import codegen

proc binop(t, s, l, r):
    return ast.binary_expr(l, token.Token(t, s), r)

let av = ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "a", 1))
let bv = ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "b", 1))

let p = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "a", 1), ast.number_expr(7))
p.next = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "b", 1), ast.number_expr(3))
p.next.next = ast.print_stmt(binop(token.TOKEN_PLUS, "+", av, bv))
p.next.next.next = ast.print_stmt(binop(token.TOKEN_PERCENT, "%", av, bv))
p.next.next.next.next = ast.print_stmt(binop(token.TOKEN_GT, ">", av, bv))
p.next.next.next.next.next = ast.print_stmt(ast.bool_expr(true))
p.next.next.next.next.next.next = ast.print_stmt(ast.bool_expr(false))
p.next.next.next.next.next.next.next = ast.print_stmt(ast.nil_expr())
p.next.next.next.next.next.next.next.next = ast.print_stmt(
    ast.string_expr("sage"))

io.writefile("/tmp/sage_codegen_rv64.s", codegen.compile_to_asm(p, codegen.TARGET_RV64))
print("wrote /tmp/sage_codegen_rv64.s")
