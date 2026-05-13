gc_disable()
# Tests for compiler.sage (C backend code generation)
import token
import ast
import compiler

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

proc assert_contains(haystack, needle, msg):
    if contains(haystack, needle):
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (not found: " + needle + ")"

proc assert_not_contains(haystack, needle, msg):
    if contains(haystack, needle):
        failed = failed + 1
        print "FAIL: " + msg + " (should not contain: " + needle + ")"
    else:
        passed = passed + 1

# Helper: make a token
proc make_tok(text):
    let t = token.Token(59, text, 1)
    return t

proc make_tok_type(text, tt):
    let t = token.Token(tt, text, 1)
    return t

# ============================================================================
# CCompiler State
# ============================================================================

let cc = compiler.CCompiler()
assert_eq(cc.indent, 0, "initial indent")
assert_eq(cc.next_unique_id, 1, "initial unique id")
assert_eq(len(cc.globals), 0, "initial globals empty")
assert_eq(len(cc.procs), 0, "initial procs empty")
assert_eq(len(cc.classes), 0, "initial classes empty")
assert_eq(cc.failed, false, "initial not failed")

# ============================================================================
# sanitize_identifier
# ============================================================================

assert_eq(compiler.sanitize_identifier("hello"), "hello", "sanitize simple")
assert_eq(compiler.sanitize_identifier("my_var"), "my_var", "sanitize underscore")
assert_eq(compiler.sanitize_identifier("123"), "_123", "sanitize leading digit")
assert_eq(compiler.sanitize_identifier("a-b"), "a_b", "sanitize dash")
assert_eq(compiler.sanitize_identifier(""), "_", "sanitize empty")
assert_eq(compiler.sanitize_identifier("CamelCase"), "CamelCase", "sanitize mixed case")

# ============================================================================
# escape_c_string
# ============================================================================

assert_eq(compiler.escape_c_string("hello"), "hello", "escape simple")
let bs = chr(92)
let dq = chr(34)
let nl = chr(10)
assert_contains(compiler.escape_c_string(dq), bs, "escape dquote has backslash")
assert_contains(compiler.escape_c_string(nl), "n", "escape newline has n")

# ============================================================================
# Name Entry Management
# ============================================================================

let cc2 = compiler.CCompiler()
let test_list = []
let e1 = compiler.add_name_entry(cc2, test_list, "foo", "sage_local")
assert_eq(e1["sage_name"], "foo", "name entry sage_name")
assert_true(contains(e1["c_name"], "sage_local"), "name entry c_name has prefix")
assert_eq(len(test_list), 1, "list has 1 entry")

# Adding same name returns existing
let e2 = compiler.add_name_entry(cc2, test_list, "foo", "sage_local")
assert_eq(len(test_list), 1, "duplicate not added")

# Different name
let e3 = compiler.add_name_entry(cc2, test_list, "bar", "sage_local")
assert_eq(len(test_list), 2, "second entry added")

# find_name_entry
let found = compiler.find_name_entry(test_list, "foo")
assert_true(found != nil, "find_name_entry found")
let not_found = compiler.find_name_entry(test_list, "baz")
assert_eq(not_found, nil, "find_name_entry not found")

# ============================================================================
# Proc Entry Management
# ============================================================================

let cc3 = compiler.CCompiler()
let p1 = compiler.add_proc_entry(cc3, "my_func", 2)
assert_eq(p1["sage_name"], "my_func", "proc entry name")
assert_eq(p1["param_count"], 2, "proc entry param count")
assert_eq(len(cc3.procs), 1, "one proc")

# Duplicate
let p2 = compiler.add_proc_entry(cc3, "my_func", 2)
assert_eq(len(cc3.procs), 1, "duplicate proc not added")

# Different proc
let p3 = compiler.add_proc_entry(cc3, "other_func", 0)
assert_eq(len(cc3.procs), 2, "two procs")

# ============================================================================
# Class Info Management
# ============================================================================

let cc4 = compiler.CCompiler()
compiler.add_class_info(cc4, "Animal", nil, nil)
assert_eq(len(cc4.classes), 1, "one class")
assert_eq(cc4.classes[0]["class_name"], "Animal", "class name")
assert_eq(cc4.classes[0]["parent_name"], nil, "no parent")

compiler.add_class_info(cc4, "Dog", "Animal", nil)
assert_eq(len(cc4.classes), 2, "two classes")
assert_eq(cc4.classes[1]["parent_name"], "Animal", "parent name")

let found_cls = compiler.find_class_info(cc4.classes, "Dog")
assert_true(found_cls != nil, "find class info")
assert_eq(found_cls["class_name"], "Dog", "found class name")

# ============================================================================
# Symbol Collection
# ============================================================================

# Build a simple program: let x = 1
let let_name_tok = make_tok("x")
let let_s = ast.let_stmt(let_name_tok, ast.number_expr(1))

let cc5 = compiler.CCompiler()
compiler.collect_top_level_symbols(cc5, let_s)
assert_true(len(cc5.globals) > 0, "global collected")
assert_true(compiler.find_name_entry(cc5.globals, "x") != nil, "x in globals")

# Build: proc foo(a, b): return a
let proc_tok = make_tok("foo")
let param_a = make_tok("a")
let param_b = make_tok("b")
let ret_body = ast.return_stmt(ast.variable_expr(param_a))
let proc_s = ast.proc_stmt(proc_tok, [param_a, param_b], ret_body)

let cc6 = compiler.CCompiler()
compiler.collect_top_level_symbols(cc6, proc_s)
assert_true(compiler.find_proc_entry(cc6.procs, "foo") != nil, "foo proc collected")
let foo_proc = compiler.find_proc_entry(cc6.procs, "foo")
assert_eq(foo_proc["param_count"], 2, "foo has 2 params")

# ============================================================================
# resolve_slot_name
# ============================================================================

let cc7 = compiler.CCompiler()
compiler.add_name_entry(cc7, cc7.globals, "x", "sage_global")
let slot = compiler.resolve_slot_name(cc7, "x")
assert_true(slot != nil, "resolve global slot")
assert_true(contains(slot, "sage_global"), "slot has global prefix")

let no_slot = compiler.resolve_slot_name(cc7, "nonexistent")
assert_eq(no_slot, nil, "no slot for unknown var")

# ============================================================================
# Expression Emission
# ============================================================================

# Number
let cc8 = compiler.CCompiler()
let num_c = compiler.cc_emit_expr(cc8, ast.number_expr(42))
assert_contains(num_c, "sage_number(42", "number emission")

# String
let str_c = compiler.cc_emit_expr(cc8, ast.string_expr("hello"))
assert_contains(str_c, "sage_string(", "string emission has sage_string")
assert_contains(str_c, "hello", "string emission has value")

# Bool true
let bool_c = compiler.cc_emit_expr(cc8, ast.bool_expr(true))
assert_eq(bool_c, "sage_bool(1)", "bool true emission")

# Bool false
let bool_f = compiler.cc_emit_expr(cc8, ast.bool_expr(false))
assert_eq(bool_f, "sage_bool(0)", "bool false emission")

# Nil
let nil_c = compiler.cc_emit_expr(cc8, ast.nil_expr())
assert_eq(nil_c, "sage_nil()", "nil emission")

# Variable (needs slot)
let cc9 = compiler.CCompiler()
compiler.add_name_entry(cc9, cc9.globals, "myvar", "sage_global")
let var_c = compiler.cc_emit_expr(cc9, ast.variable_expr(make_tok("myvar")))
assert_contains(var_c, "sage_load_slot", "variable loads slot")
assert_contains(var_c, "myvar", "variable has name")

# Binary: 1 + 2
let plus_tok = make_tok_type("+", 34)
let bin_expr = ast.binary_expr(ast.number_expr(1), plus_tok, ast.number_expr(2))
let bin_c = compiler.cc_emit_expr(cc8, bin_expr)
assert_contains(bin_c, "sage_add(", "binary add emission")

# Binary: a == b
let eq_tok = make_tok_type("==", 40)
let eq_expr = ast.binary_expr(ast.number_expr(1), eq_tok, ast.number_expr(2))
let eq_c = compiler.cc_emit_expr(cc8, eq_expr)
assert_contains(eq_c, "sage_eq(", "binary eq emission")

# Binary: not x
let not_tok = make_tok_type("not", 11)
let not_expr = ast.binary_expr(ast.bool_expr(true), not_tok, nil)
let not_c = compiler.cc_emit_expr(cc8, not_expr)
assert_contains(not_c, "sage_not(", "not emission")

# Array
let arr_expr = ast.array_expr([ast.number_expr(1), ast.number_expr(2)])
let arr_c = compiler.cc_emit_expr(cc8, arr_expr)
assert_contains(arr_c, "sage_make_array(2", "array emission count")

# Empty array
let earr_c = compiler.cc_emit_expr(cc8, ast.array_expr([]))
assert_contains(earr_c, "sage_make_array(0", "empty array emission")

# Dict
let dict_e = ast.dict_expr(["key"], [ast.number_expr(1)])
let dict_c = compiler.cc_emit_expr(cc8, dict_e)
assert_contains(dict_c, "sage_make_dict()", "dict emission has make_dict")
assert_contains(dict_c, "sage_dict_set", "dict emission has set")

# Tuple
let tup_e = ast.tuple_expr([ast.number_expr(1), ast.number_expr(2)])
let tup_c = compiler.cc_emit_expr(cc8, tup_e)
assert_contains(tup_c, "sage_make_tuple(2", "tuple emission")

# Index
let idx_e = ast.index_expr(ast.variable_expr(make_tok("arr")), ast.number_expr(0))
let cc10 = compiler.CCompiler()
compiler.add_name_entry(cc10, cc10.globals, "arr", "sage_global")
let idx_c = compiler.cc_emit_expr(cc10, idx_e)
assert_contains(idx_c, "sage_index(", "index emission")

# Get (property access)
let get_e = ast.get_expr(ast.variable_expr(make_tok("obj")), make_tok("prop"))
let cc11 = compiler.CCompiler()
compiler.add_name_entry(cc11, cc11.globals, "obj", "sage_global")
let get_c = compiler.cc_emit_expr(cc11, get_e)
assert_contains(get_c, "sage_index(", "get emission uses sage_index")
assert_contains(get_c, "prop", "get emission has property name")

# ============================================================================
# Builtin Call Emission
# ============================================================================

# str(x)
let str_call = ast.call_expr(ast.variable_expr(make_tok("str")), [ast.number_expr(42)])
let str_call_c = compiler.cc_emit_expr(cc8, str_call)
assert_contains(str_call_c, "sage_str(", "str() builtin")

# len(x)
let len_call = ast.call_expr(ast.variable_expr(make_tok("len")), [ast.number_expr(0)])
let len_call_c = compiler.cc_emit_expr(cc8, len_call)
assert_contains(len_call_c, "sage_len(", "len() builtin")

# push(a, b)
let push_call = ast.call_expr(ast.variable_expr(make_tok("push")), [ast.number_expr(0), ast.number_expr(1)])
let push_call_c = compiler.cc_emit_expr(cc8, push_call)
assert_contains(push_call_c, "sage_push(", "push() builtin")

# pop(a)
let pop_call = ast.call_expr(ast.variable_expr(make_tok("pop")), [ast.number_expr(0)])
let pop_call_c = compiler.cc_emit_expr(cc8, pop_call)
assert_contains(pop_call_c, "sage_pop(", "pop() builtin")

# range(n)
let range1_call = ast.call_expr(ast.variable_expr(make_tok("range")), [ast.number_expr(10)])
let range1_c = compiler.cc_emit_expr(cc8, range1_call)
assert_contains(range1_c, "sage_range1(", "range(1) builtin")

# range(a, b)
let range2_call = ast.call_expr(ast.variable_expr(make_tok("range")), [ast.number_expr(0), ast.number_expr(10)])
let range2_c = compiler.cc_emit_expr(cc8, range2_call)
assert_contains(range2_c, "sage_range2(", "range(2) builtin")

# tonumber(x)
let tn_call = ast.call_expr(ast.variable_expr(make_tok("tonumber")), [ast.string_expr("42")])
let tn_c = compiler.cc_emit_expr(cc8, tn_call)
assert_contains(tn_c, "sage_tonumber(", "tonumber() builtin")

# dict_keys
let dk_call = ast.call_expr(ast.variable_expr(make_tok("dict_keys")), [ast.nil_expr()])
let dk_c = compiler.cc_emit_expr(cc8, dk_call)
assert_contains(dk_c, "sage_dict_keys_fn(", "dict_keys() builtin")

# dict_has
let dh_call = ast.call_expr(ast.variable_expr(make_tok("dict_has")), [ast.nil_expr(), ast.string_expr("k")])
let dh_c = compiler.cc_emit_expr(cc8, dh_call)
assert_contains(dh_c, "sage_dict_has_fn(", "dict_has() builtin")

# upper
let up_call = ast.call_expr(ast.variable_expr(make_tok("upper")), [ast.string_expr("hi")])
let up_c = compiler.cc_emit_expr(cc8, up_call)
assert_contains(up_c, "sage_upper(", "upper() builtin")

# lower
let lo_call = ast.call_expr(ast.variable_expr(make_tok("lower")), [ast.string_expr("HI")])
let lo_c = compiler.cc_emit_expr(cc8, lo_call)
assert_contains(lo_c, "sage_lower(", "lower() builtin")

# split
let sp_call = ast.call_expr(ast.variable_expr(make_tok("split")), [ast.string_expr("a,b"), ast.string_expr(",")])
let sp_c = compiler.cc_emit_expr(cc8, sp_call)
assert_contains(sp_c, "sage_split_fn(", "split() builtin")

# join
let jn_call = ast.call_expr(ast.variable_expr(make_tok("join")), [ast.nil_expr(), ast.string_expr(",")])
let jn_c = compiler.cc_emit_expr(cc8, jn_call)
assert_contains(jn_c, "sage_join_fn(", "join() builtin")

# replace
let rp_call = ast.call_expr(ast.variable_expr(make_tok("replace")), [ast.string_expr("ab"), ast.string_expr("a"), ast.string_expr("c")])
let rp_c = compiler.cc_emit_expr(cc8, rp_call)
assert_contains(rp_c, "sage_replace_fn(", "replace() builtin")

# clock
let clk_call = ast.call_expr(ast.variable_expr(make_tok("clock")), [])
let clk_c = compiler.cc_emit_expr(cc8, clk_call)
assert_eq(clk_c, "sage_clock_fn()", "clock() builtin")

# input()
let inp_call = ast.call_expr(ast.variable_expr(make_tok("input")), [])
let inp_c = compiler.cc_emit_expr(cc8, inp_call)
assert_contains(inp_c, "sage_input_fn(", "input() builtin")

# asm_arch
let arch_call = ast.call_expr(ast.variable_expr(make_tok("asm_arch")), [])
let arch_c = compiler.cc_emit_expr(cc8, arch_call)
assert_eq(arch_c, "sage_arch_fn()", "asm_arch() builtin")

# User-defined function call
let cc12 = compiler.CCompiler()
compiler.add_proc_entry(cc12, "myfunc", 1)
let user_call = ast.call_expr(ast.variable_expr(make_tok("myfunc")), [ast.number_expr(5)])
let user_c = compiler.cc_emit_expr(cc12, user_call)
assert_contains(user_c, "sage_fn", "user call has sage_fn prefix")
assert_contains(user_c, "sage_number(5", "user call has argument")

# ============================================================================
# Statement Emission
# ============================================================================

# print
let cc13 = compiler.CCompiler()
compiler.cc_emit_stmt(cc13, ast.print_stmt(ast.number_expr(42)))
let print_out = join(cc13.output, "")
assert_contains(print_out, "sage_print_ln(", "print stmt")

# let
let cc14 = compiler.CCompiler()
let let_tok = make_tok("mylet")
compiler.add_name_entry(cc14, cc14.globals, "mylet", "sage_global")
compiler.cc_emit_stmt(cc14, ast.let_stmt(let_tok, ast.number_expr(10)))
let let_out = join(cc14.output, "")
assert_contains(let_out, "sage_define_slot(", "let stmt defines slot")

# return
let cc15 = compiler.CCompiler()
compiler.cc_emit_stmt(cc15, ast.return_stmt(ast.number_expr(0)))
let ret_out = join(cc15.output, "")
assert_contains(ret_out, "return sage_number(0", "return stmt")

# return nil
let cc16 = compiler.CCompiler()
compiler.cc_emit_stmt(cc16, ast.return_stmt(nil))
let ret_nil_out = join(cc16.output, "")
assert_contains(ret_nil_out, "return sage_nil()", "return nil stmt")

# break
let cc17 = compiler.CCompiler()
compiler.cc_emit_stmt(cc17, ast.break_stmt())
let brk_out = join(cc17.output, "")
assert_contains(brk_out, "break;", "break stmt")

# continue
let cc18 = compiler.CCompiler()
compiler.cc_emit_stmt(cc18, ast.continue_stmt())
let cont_out = join(cc18.output, "")
assert_contains(cont_out, "continue;", "continue stmt")

# if
let cc19 = compiler.CCompiler()
let if_body = ast.print_stmt(ast.number_expr(1))
let if_s = ast.if_stmt(ast.bool_expr(true), if_body, nil)
compiler.cc_emit_stmt(cc19, if_s)
let if_out = join(cc19.output, "")
assert_contains(if_out, "if (sage_truthy(", "if stmt condition")
assert_contains(if_out, "sage_print_ln(", "if stmt body")

# if/else
let cc20 = compiler.CCompiler()
let else_body = ast.print_stmt(ast.number_expr(2))
let ifelse_s = ast.if_stmt(ast.bool_expr(true), ast.print_stmt(ast.number_expr(1)), else_body)
compiler.cc_emit_stmt(cc20, ifelse_s)
let ifelse_out = join(cc20.output, "")
assert_contains(ifelse_out, "else {", "if/else has else")

# while
let cc21 = compiler.CCompiler()
let while_s = ast.while_stmt(ast.bool_expr(true), ast.break_stmt())
compiler.cc_emit_stmt(cc21, while_s)
let while_out = join(cc21.output, "")
assert_contains(while_out, "while (sage_truthy(", "while condition")

# for
let cc22 = compiler.CCompiler()
let for_var_tok = make_tok("i")
compiler.add_name_entry(cc22, cc22.globals, "i", "sage_global")
let for_body = ast.print_stmt(ast.variable_expr(for_var_tok))
let for_s = ast.for_stmt(for_var_tok, ast.call_expr(ast.variable_expr(make_tok("range")), [ast.number_expr(10)]), for_body)
compiler.cc_emit_stmt(cc22, for_s)
let for_out = join(cc22.output, "")
assert_contains(for_out, "SAGE_TAG_ARRAY", "for handles array")
assert_contains(for_out, "SAGE_TAG_STRING", "for handles string")
assert_contains(for_out, "sage_define_slot(", "for assigns loop var")

# ============================================================================
# Function Definition Emission
# ============================================================================

let cc23 = compiler.CCompiler()
let fn_tok = make_tok("add")
let fn_param_a = make_tok("a")
let fn_param_b = make_tok("b")
let fn_plus = make_tok_type("+", 34)
let fn_body = ast.return_stmt(ast.binary_expr(ast.variable_expr(fn_param_a), fn_plus, ast.variable_expr(fn_param_b)))
let fn_stmt = ast.proc_stmt(fn_tok, [fn_param_a, fn_param_b], fn_body)
compiler.add_proc_entry(cc23, "add", 2)
compiler.emit_function_definition(cc23, fn_stmt)
let fn_out = join(cc23.output, "")
assert_contains(fn_out, "static SageValue", "function has static SageValue")
assert_contains(fn_out, "SageValue arg0", "function has arg0")
assert_contains(fn_out, "SageValue arg1", "function has arg1")
assert_contains(fn_out, "sage_define_slot(", "function binds params")
assert_contains(fn_out, "sage_add(", "function body has add")
assert_contains(fn_out, "return sage_nil();", "function has default return")

# ============================================================================
# Runtime Prelude
# ============================================================================

let cc24 = compiler.CCompiler()
compiler.emit_runtime_prelude(cc24)
let prelude = join(cc24.output, "")
assert_contains(prelude, "typedef struct SageValue SageValue;", "prelude has SageValue typedef")
assert_contains(prelude, "SAGE_TAG_NIL", "prelude has tag nil")
assert_contains(prelude, "SAGE_TAG_NUMBER", "prelude has tag number")
assert_contains(prelude, "SAGE_TAG_STRING", "prelude has tag string")
assert_contains(prelude, "SAGE_TAG_ARRAY", "prelude has tag array")
assert_contains(prelude, "SAGE_TAG_DICT", "prelude has tag dict")
assert_contains(prelude, "static SageValue sage_nil(void)", "prelude has sage_nil")
assert_contains(prelude, "static SageValue sage_number(double value)", "prelude has sage_number")
assert_contains(prelude, "static SageValue sage_string(const char* value)", "prelude has sage_string")
assert_contains(prelude, "static SageValue sage_add(", "prelude has sage_add")
assert_contains(prelude, "static SageValue sage_sub(", "prelude has sage_sub")
assert_contains(prelude, "static SageValue sage_mul(", "prelude has sage_mul")
assert_contains(prelude, "static SageValue sage_div(", "prelude has sage_div")
assert_contains(prelude, "static int sage_truthy(", "prelude has sage_truthy")
assert_contains(prelude, "static void sage_print_ln(", "prelude has print_ln")
assert_contains(prelude, "static SageValue sage_str(", "prelude has sage_str")
assert_contains(prelude, "static SageValue sage_len(", "prelude has sage_len")
assert_contains(prelude, "static SageValue sage_index(", "prelude has sage_index")
assert_contains(prelude, "static SageValue sage_push(", "prelude has sage_push")
assert_contains(prelude, "static SageValue sage_pop(", "prelude has sage_pop")
assert_contains(prelude, "static SageValue sage_range1(", "prelude has range1")
assert_contains(prelude, "static SageValue sage_range2(", "prelude has range2")
assert_contains(prelude, "sage_make_dict(void)", "prelude has make_dict")
assert_contains(prelude, "sage_dict_set(", "prelude has dict_set")
assert_contains(prelude, "sage_dict_get(", "prelude has dict_get")
assert_contains(prelude, "sage_make_tuple(", "prelude has make_tuple")
assert_contains(prelude, "sage_tonumber(", "prelude has tonumber")
assert_contains(prelude, "sage_upper(", "prelude has upper")
assert_contains(prelude, "sage_lower(", "prelude has lower")
assert_contains(prelude, "sage_split_fn(", "prelude has split")
assert_contains(prelude, "sage_join_fn(", "prelude has join")
assert_contains(prelude, "sage_replace_fn(", "prelude has replace")
assert_contains(prelude, "sage_clock_fn(", "prelude has clock")
assert_contains(prelude, "sage_input_fn(", "prelude has input")
assert_contains(prelude, "sage_arch_fn(", "prelude has arch")
assert_contains(prelude, "sage_call_method(", "prelude has call_method")
assert_contains(prelude, "sage_construct(", "prelude has construct")
assert_contains(prelude, "sage_register_class(", "prelude has register_class")
assert_contains(prelude, "sage_register_method(", "prelude has register_method")
assert_contains(prelude, "#include <setjmp.h>", "prelude has setjmp")
assert_contains(prelude, "#include <stdio.h>", "prelude has stdio")
assert_contains(prelude, "#include <stdlib.h>", "prelude has stdlib")
assert_contains(prelude, "sage_raise(", "prelude has raise")
assert_contains(prelude, "SAGE_MAX_TRY_DEPTH", "prelude has try depth")
assert_contains(prelude, "sage_values_equal(", "prelude has values_equal")
assert_contains(prelude, "sage_bit_and(", "prelude has bit_and")
assert_contains(prelude, "sage_bit_or(", "prelude has bit_or")
assert_contains(prelude, "sage_lshift(", "prelude has lshift")
assert_contains(prelude, "sage_rshift(", "prelude has rshift")
assert_contains(prelude, "sage_dict_keys_fn(", "prelude has dict_keys")
assert_contains(prelude, "sage_dict_values_fn(", "prelude has dict_values")
assert_contains(prelude, "sage_dict_has_fn(", "prelude has dict_has")
assert_contains(prelude, "sage_dict_delete_fn(", "prelude has dict_delete")
assert_contains(prelude, "sage_strip_fn(", "prelude has strip")
assert_contains(prelude, "sage_index_set(", "prelude has index_set")

# ============================================================================
# Full Compilation Pipeline
# ============================================================================

# Simple: print 42
let simple_prog = ast.print_stmt(ast.number_expr(42))
let simple_c = compiler.compile_to_c(simple_prog)
assert_contains(simple_c, "int main(void)", "full compile has main")
assert_contains(simple_c, "sage_print_ln(", "full compile has print")
assert_contains(simple_c, "return 0;", "full compile returns 0")

# Program with let
let let_prog_tok = make_tok("x")
let let_prog = ast.let_stmt(let_prog_tok, ast.number_expr(5))
let print_x = ast.print_stmt(ast.variable_expr(let_prog_tok))
let_prog.next = print_x
let let_prog_c = compiler.compile_to_c(let_prog)
assert_contains(let_prog_c, "static SageSlot", "let program has SageSlot")
assert_contains(let_prog_c, "sage_define_slot(", "let program defines slot")
assert_contains(let_prog_c, "sage_load_slot(", "let program loads slot")

# Program with proc
let proc_tok2 = make_tok("double_it")
let proc_param = make_tok("n")
let mul_tok = make_tok_type("*", 36)
let proc_body = ast.return_stmt(ast.binary_expr(ast.variable_expr(proc_param), mul_tok, ast.number_expr(2)))
let proc_def = ast.proc_stmt(proc_tok2, [proc_param], proc_body)
let call_it = ast.print_stmt(ast.call_expr(ast.variable_expr(make_tok("double_it")), [ast.number_expr(21)]))
proc_def.next = call_it
let proc_c = compiler.compile_to_c(proc_def)
assert_contains(proc_c, "static SageValue sage_fn_", "proc compile has function")
assert_contains(proc_c, "sage_mul(", "proc compile has mul")
assert_contains(proc_c, "int main(void)", "proc compile has main")

# Program with class
let init_tok = make_tok("init")
let self_tok = make_tok("self")
let val_tok = make_tok("val")
let init_body = ast.expr_stmt(ast.set_expr(ast.variable_expr(self_tok), make_tok("value"), ast.variable_expr(val_tok)))
let init_method = ast.proc_stmt(init_tok, [self_tok, val_tok], init_body)
let class_name_tok = make_tok("MyClass")
let cls_stmt = ast.class_stmt(class_name_tok, nil, false, init_method)
let make_inst = ast.print_stmt(ast.call_expr(ast.variable_expr(make_tok("MyClass")), [ast.number_expr(10)]))
cls_stmt.next = make_inst
let cls_c = compiler.compile_to_c(cls_stmt)
assert_contains(cls_c, "sage_method_MyClass_init", "class compile has method")
assert_contains(cls_c, "sage_register_class(", "class compile registers class")
assert_contains(cls_c, "sage_register_method(", "class compile registers method")
assert_contains(cls_c, "sage_construct(", "class compile constructs")

# Empty program
let empty_prog = ast.print_stmt(ast.nil_expr())
let empty_c = compiler.compile_to_c(empty_prog)
assert_contains(empty_c, "int main(void)", "empty prog has main")

# ============================================================================
# Edge Cases
# ============================================================================

# Set expression (assignment)
let cc25 = compiler.CCompiler()
compiler.add_name_entry(cc25, cc25.globals, "x", "sage_global")
let set_e = ast.set_expr(nil, make_tok("x"), ast.number_expr(5))
let set_c = compiler.cc_emit_expr(cc25, set_e)
assert_contains(set_c, "sage_assign_slot(", "set expr assigns")

# Property set expression
let cc26 = compiler.CCompiler()
compiler.add_name_entry(cc26, cc26.globals, "obj", "sage_global")
let pset_e = ast.set_expr(ast.variable_expr(make_tok("obj")), make_tok("field"), ast.number_expr(1))
let pset_c = compiler.cc_emit_expr(cc26, pset_e)
assert_contains(pset_c, "sage_dict_set(", "property set uses dict_set")

# Index set expression
let cc27 = compiler.CCompiler()
compiler.add_name_entry(cc27, cc27.globals, "arr", "sage_global")
let iset_e = ast.index_set_expr(ast.variable_expr(make_tok("arr")), ast.number_expr(0), ast.number_expr(99))
let iset_c = compiler.cc_emit_expr(cc27, iset_e)
assert_contains(iset_c, "sage_index_set(", "index set emission")

# Method call
let cc28 = compiler.CCompiler()
compiler.add_name_entry(cc28, cc28.globals, "obj", "sage_global")
let method_callee = ast.get_expr(ast.variable_expr(make_tok("obj")), make_tok("do_something"))
let method_call = ast.call_expr(method_callee, [ast.number_expr(1)])
let method_c = compiler.cc_emit_expr(cc28, method_call)
assert_contains(method_c, "sage_call_method(", "method call emission")
assert_contains(method_c, "do_something", "method call has method name")

# Slice expression
let cc29 = compiler.CCompiler()
compiler.add_name_entry(cc29, cc29.globals, "arr", "sage_global")
let slice_e = ast.slice_expr(ast.variable_expr(make_tok("arr")), ast.number_expr(1), ast.number_expr(3))
let slice_c = compiler.cc_emit_expr(cc29, slice_e)
assert_contains(slice_c, "sage_slice(", "slice emission")

# Multiple binary operators
let sub_tok = make_tok_type("-", 35)
let sub_c = compiler.cc_emit_expr(cc8, ast.binary_expr(ast.number_expr(5), sub_tok, ast.number_expr(3)))
assert_contains(sub_c, "sage_sub(", "sub emission")

let mul_tok2 = make_tok_type("*", 36)
let mul_c = compiler.cc_emit_expr(cc8, ast.binary_expr(ast.number_expr(2), mul_tok2, ast.number_expr(3)))
assert_contains(mul_c, "sage_mul(", "mul emission")

let div_tok = make_tok_type("/", 37)
let div_c = compiler.cc_emit_expr(cc8, ast.binary_expr(ast.number_expr(6), div_tok, ast.number_expr(2)))
assert_contains(div_c, "sage_div(", "div emission")

let mod_tok = make_tok_type("%", 38)
let mod_c = compiler.cc_emit_expr(cc8, ast.binary_expr(ast.number_expr(7), mod_tok, ast.number_expr(3)))
assert_contains(mod_c, "sage_mod(", "mod emission")

let gt_tok = make_tok_type(">", 43)
let gt_c = compiler.cc_emit_expr(cc8, ast.binary_expr(ast.number_expr(5), gt_tok, ast.number_expr(3)))
assert_contains(gt_c, "sage_gt(", "gt emission")

let lt_tok = make_tok_type("<", 42)
let lt_c = compiler.cc_emit_expr(cc8, ast.binary_expr(ast.number_expr(3), lt_tok, ast.number_expr(5)))
assert_contains(lt_c, "sage_lt(", "lt emission")

let and_tok = make_tok_type("and", 9)
let and_c = compiler.cc_emit_expr(cc8, ast.binary_expr(ast.bool_expr(true), and_tok, ast.bool_expr(false)))
assert_contains(and_c, "sage_and(", "and emission")

let or_tok = make_tok_type("or", 10)
let or_c = compiler.cc_emit_expr(cc8, ast.binary_expr(ast.bool_expr(true), or_tok, ast.bool_expr(false)))
assert_contains(or_c, "sage_or(", "or emission")

# ============================================================================
# Summary
# ============================================================================

print ""
print "C Compiler Tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All C compiler tests passed!"
