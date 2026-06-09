gc_disable()
# Tests for llvm_backend.sage (LLVM IR text generation)
import token
import ast
import llvm_backend

let passed = 0
let failed = 0

proc assert_true(v, msg):
    if v:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg

proc assert_eq(a, b, msg):
    if a == b:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (got " + str(a) + ", expected " + str(b) + ")"

proc assert_not_contains(haystack, needle, msg):
    if contains(haystack, needle):
        failed = failed + 1
        print "FAIL: " + msg + " (unexpected: " + needle + ")"
    else:
        passed = passed + 1

# ============================================================================
# LLVMCompiler State
# ============================================================================

let lc = llvm_backend.LLVMCompiler()
assert_eq(lc.next_reg, 0, "initial next_reg")
assert_eq(lc.next_label, 0, "initial next_label")
assert_eq(lc.string_count, 0, "initial string_count")
assert_eq(lc.loop_depth, 0, "initial loop_depth")
assert_eq(lc.failed, false, "initial failed")

# --- llc_new_reg ---
let r0 = llvm_backend.llc_new_reg(lc)
assert_eq(r0, 0, "new_reg first")
let r1 = llvm_backend.llc_new_reg(lc)
assert_eq(r1, 1, "new_reg second")
assert_eq(lc.next_reg, 2, "next_reg after 2 allocs")

# --- llc_new_label ---
let l0 = llvm_backend.llc_new_label(lc)
assert_eq(l0, 0, "new_label first")
let l1 = llvm_backend.llc_new_label(lc)
assert_eq(l1, 1, "new_label second")

# --- llc_add_string ---
let s0 = llvm_backend.llc_add_string(lc, "hello")
assert_eq(s0, 0, "add_string first idx")
let s1 = llvm_backend.llc_add_string(lc, "world")
assert_eq(s1, 1, "add_string second idx")
assert_eq(lc.string_count, 2, "string_count after 2 adds")
assert_eq(lc.strings[0], "hello", "string 0 value")
assert_eq(lc.strings[1], "world", "string 1 value")

# --- llc_add_proc / llc_add_global ---
llvm_backend.llc_add_proc(lc, "myfunc")
assert_eq(len(lc.proc_names), 1, "proc_names count")
assert_eq(lc.proc_names[0], "myfunc", "proc name")

llvm_backend.llc_add_global(lc, "myvar")
assert_eq(len(lc.global_names), 1, "global_names count")
assert_eq(lc.global_names[0], "myvar", "global name")

# ============================================================================
# String Escaping
# ============================================================================

assert_eq(llvm_backend.llvm_escape_string("hello"), "hello", "escape plain")
assert_eq(llvm_backend.llvm_escape_string("a" + chr(10) + "b"), "a" + chr(92) + "0Ab", "escape newline")
assert_eq(llvm_backend.llvm_escape_string("a" + chr(9) + "b"), "a" + chr(92) + "09b", "escape tab")

# ============================================================================
# Symbol Collection
# ============================================================================

let lc2 = llvm_backend.LLVMCompiler()
let prog_let = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "x", 1), ast.number_expr(42))
let prog_proc = ast.proc_stmt(token.Token(token.TOKEN_IDENTIFIER, "add", 1), [token.Token(token.TOKEN_IDENTIFIER, "a", 1), token.Token(token.TOKEN_IDENTIFIER, "b", 1)], ast.return_stmt(ast.binary_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "a", 1)), token.Token(token.TOKEN_PLUS, "+", 1), ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "b", 1)))))
prog_let.next = prog_proc
llvm_backend.llvm_collect_symbols(lc2, prog_let)
assert_eq(len(lc2.global_names), 1, "collect global count")
assert_eq(lc2.global_names[0], "x", "collect global name")
assert_eq(len(lc2.proc_names), 1, "collect proc count")
assert_eq(lc2.proc_names[0], "add", "collect proc name")

# ============================================================================
# Expression Emission
# ============================================================================

# --- Number literal ---
let lc3 = llvm_backend.LLVMCompiler()
let r_num = llvm_backend.llvm_emit_expr(lc3, ast.number_expr(42))
assert_eq(r_num, 0, "emit number reg")
let out = join(lc3.output, "")
assert_true(contains(out, "sage_rt_number"), "number calls sage_rt_number")

# --- String literal ---
let lc4 = llvm_backend.LLVMCompiler()
let r_str = llvm_backend.llvm_emit_expr(lc4, ast.string_expr("hello"))
assert_true(r_str >= 0, "emit string reg")
let out2 = join(lc4.output, "")
assert_true(contains(out2, "sage_rt_string"), "string calls sage_rt_string")
assert_true(contains(out2, "getelementptr"), "string uses getelementptr")
assert_eq(lc4.string_count, 1, "string added to pool")

# --- Bool literal ---
let lc5 = llvm_backend.LLVMCompiler()
let r_bool = llvm_backend.llvm_emit_expr(lc5, ast.bool_expr(true))
let out3 = join(lc5.output, "")
assert_true(contains(out3, "sage_rt_bool(i32 1)"), "bool true emits 1")

let lc5b = llvm_backend.LLVMCompiler()
llvm_backend.llvm_emit_expr(lc5b, ast.bool_expr(false))
let out3b = join(lc5b.output, "")
assert_true(contains(out3b, "sage_rt_bool(i32 0)"), "bool false emits 0")

# --- Nil literal ---
let lc6 = llvm_backend.LLVMCompiler()
llvm_backend.llvm_emit_expr(lc6, ast.nil_expr())
let out4 = join(lc6.output, "")
assert_true(contains(out4, "sage_rt_nil"), "nil calls sage_rt_nil")

# --- Binary: addition ---
let lc7 = llvm_backend.LLVMCompiler()
let bin = ast.binary_expr(ast.number_expr(1), token.Token(token.TOKEN_PLUS, "+", 1), ast.number_expr(2))
llvm_backend.llvm_emit_expr(lc7, bin)
let out5 = join(lc7.output, "")
assert_true(contains(out5, "sage_rt_add"), "binary + calls sage_rt_add")

# --- Binary: subtraction ---
let lc7b = llvm_backend.LLVMCompiler()
let bin_sub = ast.binary_expr(ast.number_expr(5), token.Token(token.TOKEN_MINUS, "-", 1), ast.number_expr(3))
llvm_backend.llvm_emit_expr(lc7b, bin_sub)
let out5b = join(lc7b.output, "")
assert_true(contains(out5b, "sage_rt_sub"), "binary - calls sage_rt_sub")

# --- Binary: comparison ---
let lc7c = llvm_backend.LLVMCompiler()
let bin_eq = ast.binary_expr(ast.number_expr(1), token.Token(token.TOKEN_EQ, "==", 1), ast.number_expr(1))
llvm_backend.llvm_emit_expr(lc7c, bin_eq)
let out5c = join(lc7c.output, "")
assert_true(contains(out5c, "sage_rt_eq"), "binary == calls sage_rt_eq")

# --- Binary: logical ---
let lc7d = llvm_backend.LLVMCompiler()
let bin_and = ast.binary_expr(ast.bool_expr(true), token.Token(token.TOKEN_AND, "and", 1), ast.bool_expr(false))
llvm_backend.llvm_emit_expr(lc7d, bin_and)
let out5d = join(lc7d.output, "")
assert_true(contains(out5d, "sage_rt_and"), "binary and calls sage_rt_and")

# --- Variable ---
let lc8 = llvm_backend.LLVMCompiler()
let var_e = ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "myvar", 1))
llvm_backend.llvm_emit_expr(lc8, var_e)
let out6 = join(lc8.output, "")
assert_true(contains(out6, "load"), "variable emits load")
assert_true(contains(out6, "myvar"), "variable uses name")

# --- Call: builtin str ---
let lc9 = llvm_backend.LLVMCompiler()
let call_str = ast.call_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "str", 1)), [ast.number_expr(42)])
llvm_backend.llvm_emit_expr(lc9, call_str)
let out7 = join(lc9.output, "")
assert_true(contains(out7, "sage_rt_str"), "call str emits sage_rt_str")

# --- Call: builtin len ---
let lc9b = llvm_backend.LLVMCompiler()
let call_len = ast.call_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "len", 1)), [ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "arr", 1))])
llvm_backend.llvm_emit_expr(lc9b, call_len)
let out7b = join(lc9b.output, "")
assert_true(contains(out7b, "sage_rt_len"), "call len emits sage_rt_len")

# --- Call: user function ---
let lc10 = llvm_backend.LLVMCompiler()
let call_user = ast.call_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "myfunc", 1)), [ast.number_expr(1), ast.number_expr(2)])
llvm_backend.llvm_emit_expr(lc10, call_user)
let out8 = join(lc10.output, "")
assert_true(contains(out8, "sage_fn_myfunc"), "user call emits sage_fn_<name>")

# --- Array ---
let lc11 = llvm_backend.LLVMCompiler()
let arr = ast.array_expr([ast.number_expr(1), ast.number_expr(2)])
llvm_backend.llvm_emit_expr(lc11, arr)
let out9 = join(lc11.output, "")
assert_true(contains(out9, "sage_rt_array_new(i32 2)"), "array creates with count")
assert_true(contains(out9, "sage_rt_array_set"), "array sets elements")

# --- Dict ---
let lc12 = llvm_backend.LLVMCompiler()
let d = ast.dict_expr(["a", "b"], [ast.number_expr(1), ast.number_expr(2)])
llvm_backend.llvm_emit_expr(lc12, d)
let out10 = join(lc12.output, "")
assert_true(contains(out10, "sage_rt_dict_new"), "dict creates new dict")
assert_true(contains(out10, "sage_rt_dict_set"), "dict sets entries")

# --- Tuple ---
let lc13 = llvm_backend.LLVMCompiler()
let tup = ast.tuple_expr([ast.number_expr(1)])
llvm_backend.llvm_emit_expr(lc13, tup)
let out11 = join(lc13.output, "")
assert_true(contains(out11, "sage_rt_tuple_new"), "tuple creates new")

# --- Nil expr ---
let lc14 = llvm_backend.LLVMCompiler()
let r_nil = llvm_backend.llvm_emit_expr(lc14, nil)
let out12 = join(lc14.output, "")
assert_true(contains(out12, "sage_rt_nil"), "nil expr calls sage_rt_nil")

# ============================================================================
# Statement Emission
# ============================================================================

# --- Print statement ---
let lc20 = llvm_backend.LLVMCompiler()
let print_s = ast.print_stmt(ast.number_expr(42))
llvm_backend.llvm_emit_stmt(lc20, print_s)
let out20 = join(lc20.output, "")
assert_true(contains(out20, "sage_rt_print"), "print stmt calls sage_rt_print")

# --- Let statement ---
let lc21 = llvm_backend.LLVMCompiler()
let let_s = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "x", 1), ast.number_expr(10))
llvm_backend.llvm_emit_stmt(lc21, let_s)
let out21 = join(lc21.output, "")
assert_true(contains(out21, "store"), "let stmt emits store")

# --- Return statement ---
let lc22 = llvm_backend.LLVMCompiler()
let ret_s = ast.return_stmt(ast.number_expr(5))
llvm_backend.llvm_emit_stmt(lc22, ret_s)
let out22 = join(lc22.output, "")
assert_true(contains(out22, "ret"), "return emits ret")

# --- If statement ---
let lc23 = llvm_backend.LLVMCompiler()
let if_s = ast.if_stmt(ast.bool_expr(true), ast.print_stmt(ast.number_expr(1)), nil)
llvm_backend.llvm_emit_stmt(lc23, if_s)
let out23 = join(lc23.output, "")
assert_true(contains(out23, "sage_rt_get_bool"), "if calls get_bool")
assert_true(contains(out23, "icmp ne"), "if emits icmp")
assert_true(contains(out23, "br i1"), "if emits conditional branch")

# --- If/else statement ---
let lc24 = llvm_backend.LLVMCompiler()
let if_else_s = ast.if_stmt(ast.bool_expr(true), ast.print_stmt(ast.number_expr(1)), ast.print_stmt(ast.number_expr(2)))
llvm_backend.llvm_emit_stmt(lc24, if_else_s)
let out24 = join(lc24.output, "")
# Should have 3 labels: then, else, merge
assert_true(contains(out24, "L0:"), "if/else has then label")
assert_true(contains(out24, "L1:"), "if/else has else label")
assert_true(contains(out24, "L2:"), "if/else has merge label")

# --- While statement ---
let lc25 = llvm_backend.LLVMCompiler()
let while_s = ast.while_stmt(ast.bool_expr(true), ast.print_stmt(ast.number_expr(1)))
llvm_backend.llvm_emit_stmt(lc25, while_s)
let out25 = join(lc25.output, "")
assert_true(contains(out25, "br label"), "while has branch to cond")
assert_true(contains(out25, "sage_rt_get_bool"), "while checks condition")

# --- Break / Continue ---
let lc26 = llvm_backend.LLVMCompiler()
push(lc26.loop_cond_labels, 5)
push(lc26.loop_end_labels, 6)
lc26.loop_depth = 1
let break_s = ast.break_stmt()
llvm_backend.llvm_emit_stmt(lc26, break_s)
let out26 = join(lc26.output, "")
assert_true(contains(out26, "br label"), "break emits branch")
assert_true(contains(out26, "L6"), "break jumps to end label")

let lc27 = llvm_backend.LLVMCompiler()
push(lc27.loop_cond_labels, 10)
push(lc27.loop_end_labels, 11)
lc27.loop_depth = 1
let cont_s = ast.continue_stmt()
llvm_backend.llvm_emit_stmt(lc27, cont_s)
let out27 = join(lc27.output, "")
assert_true(contains(out27, "L10"), "continue jumps to cond label")

# ============================================================================
# Function Emission
# ============================================================================

let lc30 = llvm_backend.LLVMCompiler()
let fn_body = ast.return_stmt(ast.binary_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "a", 1)), token.Token(token.TOKEN_PLUS, "+", 1), ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "b", 1))))
let fn_s = ast.proc_stmt(token.Token(token.TOKEN_IDENTIFIER, "add", 1), [token.Token(token.TOKEN_IDENTIFIER, "a", 1), token.Token(token.TOKEN_IDENTIFIER, "b", 1)], fn_body)
llvm_backend.llvm_emit_function(lc30, fn_s)
let out30 = join(lc30.output, "")
assert_true(contains(out30, "define"), "function has define")
assert_true(contains(out30, "sage_fn_add"), "function uses sage_fn_ prefix")
assert_true(contains(out30, "arg_a"), "function has param a")
assert_true(contains(out30, "arg_b"), "function has param b")
assert_true(contains(out30, "alloca"), "function allocates params")
assert_true(contains(out30, "entry:"), "function has entry label")
assert_true(contains(out30, "sage_rt_add"), "function body emits add")
assert_true(contains(out30, "ret"), "function has return")

# ============================================================================
# Full Compilation
# ============================================================================

let full_prog = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "x", 1), ast.number_expr(42))
let full_print = ast.print_stmt(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "x", 1)))
full_prog.next = full_print
let ir = llvm_backend.compile_to_llvm_ir(full_prog)
assert_true(contains(ir, "SageValue"), "full IR has SageValue type")
assert_true(contains(ir, "declare"), "full IR has runtime declarations")
assert_true(contains(ir, "@main"), "full IR has main function")
assert_true(contains(ir, "sage_rt_number"), "full IR has number call")
assert_true(contains(ir, "sage_rt_print"), "full IR has print call")
assert_true(contains(ir, "@x"), "full IR has global x")
assert_true(contains(ir, "ret i32 0"), "full IR returns 0 from main")
# String constants may or may not be present depending on the program
# (this program uses only numbers, no strings needed in pool)

# --- Full compilation with proc ---
let fn_body2 = ast.return_stmt(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "n", 1)))
let fn_s2 = ast.proc_stmt(token.Token(token.TOKEN_IDENTIFIER, "identity", 1), [token.Token(token.TOKEN_IDENTIFIER, "n", 1)], fn_body2)
let call_s = ast.expr_stmt(ast.call_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "identity", 1)), [ast.number_expr(5)]))
fn_s2.next = call_s
let ir2 = llvm_backend.compile_to_llvm_ir(fn_s2)
assert_true(contains(ir2, "sage_fn_identity"), "full IR with proc has function")
assert_true(contains(ir2, "define"), "full IR with proc has define")

# --- Full compilation with from-import constant ---
let import_stmt = ast.import_stmt("value", ["TYPE_NUMBER"], [nil], nil, 0)
let import_print = ast.print_stmt(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "TYPE_NUMBER", 1)))
import_stmt.next = import_print
let ir3 = llvm_backend.compile_to_llvm_ir(import_stmt)
assert_true(contains(ir3, "sage_rt_string"), "from-import constant emits string constructor")
assert_not_contains(ir3, "%TYPE_NUMBER", "from-import constant avoids unresolved local load")

# ============================================================================
# Type Definitions
# ============================================================================

let lc40 = llvm_backend.LLVMCompiler()
llvm_backend.emit_type_definitions(lc40)
let out40 = join(lc40.output, "")
assert_true(contains(out40, "SageValue = type"), "type defs has SageValue")
assert_true(contains(out40, "target datalayout"), "type defs has datalayout")
assert_true(contains(out40, "sage_rt_number"), "type defs declares rt_number")
assert_true(contains(out40, "sage_rt_print"), "type defs declares rt_print")
assert_true(contains(out40, "sage_rt_add"), "type defs declares rt_add")
assert_true(contains(out40, "sage_rt_dict_new"), "type defs declares rt_dict_new")

print ""
print "LLVM backend tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All LLVM backend tests passed!"
