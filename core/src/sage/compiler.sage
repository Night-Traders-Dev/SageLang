gc_disable()
# ============================================================================
# compiler.sage - C Backend Code Generator
#
# Generates standalone C source code from Sage AST.
# Emits a complete self-contained .c file with runtime, type definitions,
# function prototypes, global slots, function definitions, and main().
# Port of src/c/compiler.c
# ============================================================================
import token
import ast
from token import TOKEN_PLUS, TOKEN_MINUS, TOKEN_STAR, TOKEN_SLASH, TOKEN_PERCENT
from token import TOKEN_EQ, TOKEN_NEQ, TOKEN_LT, TOKEN_GT, TOKEN_LTE, TOKEN_GTE
from token import TOKEN_AMP, TOKEN_PIPE, TOKEN_CARET, TOKEN_TILDE
from token import TOKEN_LSHIFT, TOKEN_RSHIFT, TOKEN_AND, TOKEN_OR, TOKEN_NOT

# ============================================================================
# Character constants (Sage has no escape sequences)
# ============================================================================
let NL = chr(10)
let DQ = chr(34)
let BS = chr(92)
let TAB = chr(9)

# ============================================================================
# CCompiler State
# ============================================================================

class CCompiler:
    proc init():
        self.output = []
        self.indent = 0
        self.next_unique_id = 1
        self.globals = []
        self.procs = []
        self.locals = []
        self.anon_fns = []
        self.prebound_anons = nil
        self.prebind_active = false
        self.gen_out_var = nil
        self.gen_collector = false
        self.fn_stack = []
        self.hoisted_defs = []
        self.discovered_nested = []
        self.defer_scopes = [[]]
        self.classes = []
        self.modules = []
        self.failed = false
        self.input_path = nil

# ============================================================================
# Output Helpers
# ============================================================================

proc cc_emit(cc, text):
    push(cc.output, text)

proc cc_line(cc, text):
    let indent_str = ""
    for i in range(cc.indent):
        indent_str = indent_str + "    "
    push(cc.output, indent_str + text + NL)

proc cc_blank(cc):
    push(cc.output, NL)

# ============================================================================
# String Utilities
# ============================================================================

proc sanitize_identifier(text):
    let parts = []
    let slen = len(text)
    if slen == 0:
        push(parts, "_")
        return join(parts, "")
    let first = text[0]
    if first == "0" or first == "1" or first == "2" or first == "3" or first == "4" or first == "5" or first == "6" or first == "7" or first == "8" or first == "9":
        push(parts, "_")
    for i in range(slen):
        let ch = text[i]
        # Check if alphanumeric or underscore
        if ch == "_":
            push(parts, ch)
            continue
        if ch == "a" or ch == "b" or ch == "c" or ch == "d" or ch == "e" or ch == "f" or ch == "g" or ch == "h" or ch == "i" or ch == "j" or ch == "k" or ch == "l" or ch == "m" or ch == "n" or ch == "o" or ch == "p" or ch == "q" or ch == "r" or ch == "s" or ch == "t" or ch == "u" or ch == "v" or ch == "w" or ch == "x" or ch == "y" or ch == "z":
            push(parts, ch)
            continue
        if ch == "A" or ch == "B" or ch == "C" or ch == "D" or ch == "E" or ch == "F" or ch == "G" or ch == "H" or ch == "I" or ch == "J" or ch == "K" or ch == "L" or ch == "M" or ch == "N" or ch == "O" or ch == "P" or ch == "Q" or ch == "R" or ch == "S" or ch == "T" or ch == "U" or ch == "V" or ch == "W" or ch == "X" or ch == "Y" or ch == "Z":
            push(parts, ch)
            continue
        if ch == "0" or ch == "1" or ch == "2" or ch == "3" or ch == "4" or ch == "5" or ch == "6" or ch == "7" or ch == "8" or ch == "9":
            push(parts, ch)
            continue
        push(parts, "_")
    return join(parts, "")

proc escape_c_string(text):
    let parts = []
    for i in range(len(text)):
        let ch = text[i]
        if ch == BS:
            push(parts, BS + BS)
        if ch == DQ:
            push(parts, BS + DQ)
            continue
        if ch == NL:
            push(parts, BS + "n")
            continue
        if ch == chr(13):
            push(parts, BS + "r")
            continue
        if ch == TAB:
            push(parts, BS + "t")
            continue
        if ch != BS:
            push(parts, ch)
    return join(parts, "")

# ============================================================================
# Name/Proc/Class Entry Management
# ============================================================================

# NameEntry: {sage_name, c_name}
# ProcEntry: {sage_name, c_name, param_count}
# ClassInfo: {class_name, parent_name, methods}

proc find_name_entry(entry_list, sage_name):
    for i in range(len(entry_list)):
        if entry_list[i]["sage_name"] == sage_name:
            return entry_list[i]
    return nil

proc find_proc_entry(proc_list, sage_name):
    for i in range(len(proc_list)):
        if proc_list[i]["sage_name"] == sage_name:
            return proc_list[i]
    return nil

proc find_class_info(class_list, name):
    for i in range(len(class_list)):
        if class_list[i]["class_name"] == name:
            return class_list[i]
    return nil

proc make_unique_name(cc, prefix, sage_name):
    let sanitized = sanitize_identifier(sage_name)
    let uid = cc.next_unique_id
    cc.next_unique_id = cc.next_unique_id + 1
    return prefix + "_" + sanitized + "_" + str(uid)

proc add_name_entry(cc, entry_list, sage_name, prefix):
    let existing = find_name_entry(entry_list, sage_name)
    if existing != nil:
        return existing
    let entry = {}
    entry["sage_name"] = sage_name
    entry["c_name"] = make_unique_name(cc, prefix, sage_name)
    push(entry_list, entry)
    return entry

proc stmt_has_yield(stmt):
    if stmt == nil:
        return false
    let t = stmt.type
    if t == 116:
        return true
    if t == 104:
        return stmt_has_yield_list(stmt.statements)
    if t == 103:
        if stmt_has_yield(stmt.then_branch):
            return true
        if stmt.else_branch != nil and stmt_has_yield(stmt.else_branch):
            return true
        return false
    if t == 105 or t == 107:
        return stmt_has_yield(stmt.body)
    if t == 114:
        if stmt.try_block != nil and stmt_has_yield(stmt.try_block):
            return true
        if stmt.finally_block != nil and stmt_has_yield(stmt.finally_block):
            return true
    if t == 108 or t == 113:
        return false
    return false

proc stmt_has_yield_list(first):
    let cur = first
    while cur != nil:
        if stmt_has_yield(cur):
            return true
        cur = cur.next
    return false

proc add_proc_entry(cc, sage_name, param_count, param_defaults):
    let existing = find_proc_entry(cc.procs, sage_name)
    if existing != nil:
        return existing
    let entry = {}
    entry["sage_name"] = sage_name
    entry["c_name"] = make_unique_name(cc, "sage_fn", sage_name)
    entry["param_count"] = param_count
    entry["param_defaults"] = param_defaults
    push(cc.procs, entry)
    return entry

proc add_class_info(cc, name, parent, methods):
    let info = {}
    info["class_name"] = name
    info["parent_name"] = parent
    info["methods"] = methods
    push(cc.classes, info)
    return info

# ============================================================================
# Symbol Collection
# ============================================================================

proc collect_local_lets(cc, stmt, locals_list):
    let current = stmt
    while current != nil:
        let t = current.type
        if t == 102:
            # STMT_LET
            let name = current.name.text
            if find_name_entry(locals_list, name) == nil:
                add_name_entry(cc, locals_list, name, "sage_local")
        if t == 104:
            # STMT_BLOCK
            collect_local_lets(cc, current.statements, locals_list)
        if t == 103:
            # STMT_IF
            collect_local_lets(cc, current.then_branch, locals_list)
            if current.else_branch != nil:
                collect_local_lets(cc, current.else_branch, locals_list)
        if t == 112:
            # STMT_MATCH
            let mi7 = 0
            while mi7 < len(current.cases):
                collect_local_lets(cc, current.cases[mi7]["body"], locals_list)
                mi7 = mi7 + 1
            if current.default_case != nil:
                collect_local_lets(cc, current.default_case, locals_list)
        if t == 105:
            # STMT_WHILE
            collect_local_lets(cc, current.body, locals_list)
        if t == 107:
            # STMT_FOR
            let var_name = current.variable.text
            if find_name_entry(locals_list, var_name) == nil:
                add_name_entry(cc, locals_list, var_name, "sage_local")
            collect_local_lets(cc, current.body, locals_list)
        if t == 114:
            # STMT_TRY
            collect_local_lets(cc, current.try_block, locals_list)
            for ci in range(current.catch_count):
                let catch_var = current.catches[ci].exception_var.text
                if find_name_entry(locals_list, catch_var) == nil:
                    add_name_entry(cc, locals_list, catch_var, "sage_local")
                collect_local_lets(cc, current.catches[ci].body, locals_list)
            if current.finally_block != nil:
                collect_local_lets(cc, current.finally_block, locals_list)
        current = current.next

proc collect_global_lets(cc, stmt):
    let current = stmt
    while current != nil:
        let t = current.type
        if t == 102:
            # STMT_LET
            let name = current.name.text
            add_name_entry(cc, cc.globals, name, "sage_global")
        if t == 104:
            # STMT_BLOCK
            collect_global_lets(cc, current.statements)
        if t == 103:
            # STMT_IF
            collect_global_lets(cc, current.then_branch)
            if current.else_branch != nil:
                collect_global_lets(cc, current.else_branch)
        if t == 105:
            # STMT_WHILE
            collect_global_lets(cc, current.body)
        if t == 112:
            # STMT_MATCH: recurse into case bodies and default.
            let mi6 = 0
            while mi6 < len(current.cases):
                collect_global_lets(cc, current.cases[mi6]["body"])
                mi6 = mi6 + 1
            collect_global_lets(cc, current.default_case)
        if t == 122:
            # STMT_COMPTIME: constants declared inside comptime blocks are
            # globals like any other.
            if current.body != nil and current.body.type == 104:
                collect_global_lets(cc, current.body.statements)
            else:
                collect_global_lets(cc, current.body)
        if t == 107:
            # STMT_FOR
            let var_name = current.variable.text
            add_name_entry(cc, cc.globals, var_name, "sage_global")
            collect_global_lets(cc, current.body)
        if t == 114:
            # STMT_TRY
            collect_global_lets(cc, current.try_block)
            for ci in range(current.catch_count):
                let catch_var = current.catches[ci].exception_var.text
                add_name_entry(cc, cc.globals, catch_var, "sage_global")
                collect_global_lets(cc, current.catches[ci].body)
            if current.finally_block != nil:
                collect_global_lets(cc, current.finally_block)
        current = current.next

proc collect_top_level_symbols(cc, program):
    # First pass: procs, classes
    let stmt = program
    while stmt != nil:
        if stmt.type == 106:
            # STMT_PROC
            let pe_new = add_proc_entry(cc, stmt.name.text, stmt.param_count, stmt.param_defaults)
            pe_new["is_generator"] = stmt_has_yield(stmt.body)
        if stmt.type == 111:
            # STMT_CLASS
            let parent = nil
            if stmt.has_parent:
                parent = stmt.parent.text
            add_class_info(cc, stmt.name.text, parent, stmt.methods)
        stmt = stmt.next
    # Second pass: global lets
    let stmt2 = program
    while stmt2 != nil:
        if stmt2.type != 106 and stmt2.type != 111:
            collect_global_lets(cc, stmt2)
        stmt2 = stmt2.next

# ============================================================================
# Slot Resolution
# ============================================================================

proc expr_has_proc(expr):
    if expr == nil:
        return false
    let t = expr.type
    if t == 18:
        # EXPR_PROC
        return true
    if t == 4:
        return expr_has_proc(expr.left) or expr_has_proc(expr.right)
    if t == 6:
        if expr_has_proc(expr.callee):
            return true
        let i = 0
        while i < expr.arg_count:
            if expr_has_proc(expr.args[i]):
                return true
            i = i + 1
        return false
    if t == 7 or t == 10:
        let i = 0
        while i < expr.count:
            if expr_has_proc(expr.elements[i]):
                return true
            i = i + 1
        return false
    if t == 8:
        return expr_has_proc(expr.object) or expr_has_proc(expr.index)
    if t == 9:
        let vs = expr.values
        if vs != nil and type(vs) == "array":
            let i = 0
            while i < len(vs):
                if expr_has_proc(vs[i]):
                    return true
                i = i + 1
        return false
    if t == 12:
        return expr_has_proc(expr.object)
    if t == 13:
        if expr.object != nil and expr_has_proc(expr.object):
            return true
        return expr_has_proc(expr.value)
    if t == 14:
        return expr_has_proc(expr.array) or expr_has_proc(expr.index) or expr_has_proc(expr.value)
    if t == 17:
        return expr_has_proc(expr.expression)
    return false

proc stmt_body_has_nested_fn(stmt):
    # True when the body contains a nested function definition: either a
    # named STMT_PROC descendant or an anonymous proc expression anywhere.
    if stmt == nil:
        return false
    let t = stmt.type
    if t == 116:
        # Yield alone does not introduce a nested function.
        return false
    if t == 106:
        # Nested named procedure definition.
        return true
    if t == 18:
        return true
    if t == 100 or t == 101:
        if stmt.expression != nil and expr_has_proc(stmt.expression):
            return true
        return false
    if t == 102:
        if stmt.initializer != nil and expr_has_proc(stmt.initializer):
            return true
        return false
    if t == 103:
        if expr_has_proc(stmt.condition):
            return true
        if stmt_body_has_nested_fn(stmt.then_branch):
            return true
        if stmt.else_branch != nil and stmt_body_has_nested_fn(stmt.else_branch):
            return true
        return false
    if t == 104:
        return stmt_body_has_nested_fn_list(stmt.statements)
    if t == 105 or t == 107:
        if expr_has_proc(stmt.condition) or (t == 107 and expr_has_proc(stmt.iterable)):
            return true
        return stmt_body_has_nested_fn(stmt.body)
    if t == 108:
        if stmt.value != nil and expr_has_proc(stmt.value):
            return true
        return false
    if t == 112:
        if expr_has_proc(stmt.value):
            return true
        if stmt.cases != nil and type(stmt.cases) == "array":
            let ci = 0
            while ci < len(stmt.cases):
                let cl = stmt.cases[ci]
                if expr_has_proc(cl["pattern"]) or (cl["guard"] != nil and expr_has_proc(cl["guard"])):
                    return true
                if stmt_body_has_nested_fn(cl["body"]):
                    return true
                ci = ci + 1
        return false
    if t == 114:
        if stmt.try_block != nil and stmt_body_has_nested_fn(stmt.try_block):
            return true
        if stmt.finally_block != nil and stmt_body_has_nested_fn(stmt.finally_block):
            return true
        return false
    return false

proc stmt_body_has_nested_fn_list(first):
    let cur = first
    while cur != nil:
        if stmt_body_has_nested_fn(cur):
            return true
        cur = cur.next
    return false

# Frame helpers -----------------------------------------------------------
proc fn_push_frame(cc, frame):
    push(cc.fn_stack, frame)

proc fn_pop_frame(cc):
    pop(cc.fn_stack)

proc entry_needs_cenv(entry):
    entry["needs_cenv"] = true

proc pb_fnobj_of(entry):
    return entry["fnobj"]

proc fn_top_capturing_frame(cc):
    # Innermost PROMOTING frame (a function whose locals live in an env).
    let i = len(cc.fn_stack) - 1
    while i >= 0:
        let fr = cc.fn_stack[i]
        if fr["promoting"]:
            return fr
        i = i - 1
    return nil

proc resolve_slot_name(cc, sage_name):
    # When emitting inside a capturing-parent function whose storage was
    # promoted into an environment object, promoted names must resolve to
    # their env field even though stack-slot duplicates were also declared.
    if len(cc.fn_stack) > 0:
        let top = cc.fn_stack[len(cc.fn_stack) - 1]
        if top["promoting"] and dict_has(top["fields"], sage_name):
            return "(" + top["deref"] + "->" + top["fields"][sage_name] + ")"
    let local = find_name_entry(cc.locals, sage_name)
    if local != nil:
        return local["c_name"]
    # Captured variables: walk enclosing function environments innermost
    # first. Frames expose their fields as slot lvalues via ->field.
    let fi = len(cc.fn_stack) - 1
    while fi >= 0:
        let fr = cc.fn_stack[fi]
        if fr["promoting"] and dict_has(fr["fields"], sage_name):
            return "((" + fr["deref"] + ")->" + fr["fields"][sage_name] + ")"
        fi = fi - 1
    let global_entry = find_name_entry(cc.globals, sage_name)
    if global_entry != nil:
        return global_entry["c_name"]
    return nil

# ============================================================================
# Expression Emission (returns C code string)
# ============================================================================

proc cc_emit_array_expr(cc, expr):
    if expr.count == 0:
        return "sage_make_array(0, NULL)"
    let parts = []
    push(parts, "sage_make_array(")
    push(parts, str(expr.count))
    push(parts, ", (SageValue[]){")
    for i in range(expr.count):
        if i > 0:
            push(parts, ", ")
        push(parts, cc_emit_expr(cc, expr.elements[i]))
    push(parts, "})")
    return join(parts, "")

proc cc_emit_index_expr(cc, expr):
    let arr = cc_emit_expr(cc, expr.object)
    let idx = cc_emit_expr(cc, expr.index)
    return "sage_index(" + arr + ", " + idx + ")"

proc cc_emit_slice_expr(cc, expr):
    let arr = cc_emit_expr(cc, expr.object)
    let start_e = "sage_nil()"
    let end_e = "sage_nil()"
    if expr.start != nil:
        start_e = cc_emit_expr(cc, expr.start)
    if expr.end != nil:
        end_e = cc_emit_expr(cc, expr.end)
    return "sage_slice(" + arr + ", " + start_e + ", " + end_e + ")"

proc cc_emit_dict_expr(cc, expr):
    if expr.count == 0:
        return "sage_make_dict()"
    let parts = []
    push(parts, "({SageValue _d = sage_make_dict();")
    for i in range(expr.count):
        let escaped = escape_c_string(expr.keys[i])
        let val = cc_emit_expr(cc, expr.values[i])
        push(parts, "sage_dict_set(_d.as.dict," + DQ + escaped + DQ + "," + val + ");")
    push(parts, "_d;})")
    return join(parts, "")

proc cc_emit_tuple_expr(cc, expr):
    if expr.count == 0:
        return "sage_make_tuple(0, NULL)"
    let parts = []
    push(parts, "sage_make_tuple(")
    push(parts, str(expr.count))
    push(parts, ", (SageValue[]){")
    for i in range(expr.count):
        if i > 0:
            push(parts, ", ")
        push(parts, cc_emit_expr(cc, expr.elements[i]))
    push(parts, "})")
    return join(parts, "")

proc cc_emit_binary_expr(cc, expr):
    let left = cc_emit_expr(cc, expr.left)
    let op_type = expr.op.type
    # Unary NOT
    if op_type == TOKEN_NOT:
        return "sage_not(" + left + ")"
    # Unary bitwise NOT
    if op_type == TOKEN_TILDE:
        return "sage_bit_not(" + left + ")"
    # Short-circuit: emit inline C logical operators so the right operand is
    # only evaluated when the left does not decide the result — mirroring the
    # interpreter and the C host backend. sage_and()/sage_or() as function
    # calls would evaluate both sides unconditionally.
    if op_type == TOKEN_AND:
        return "sage_bool(sage_truthy(" + left + ") && sage_truthy(" + cc_emit_expr(cc, expr.right) + "))"
    if op_type == TOKEN_OR:
        return "sage_bool(sage_truthy(" + left + ") || sage_truthy(" + cc_emit_expr(cc, expr.right) + "))"
    let right = cc_emit_expr(cc, expr.right)
    let helper = nil
    if op_type == TOKEN_PLUS:
        helper = "sage_add"
    if op_type == TOKEN_MINUS:
        helper = "sage_sub"
    if op_type == TOKEN_STAR:
        helper = "sage_mul"
    if op_type == TOKEN_SLASH:
        helper = "sage_div"
    if op_type == TOKEN_PERCENT:
        helper = "sage_mod"
    if op_type == TOKEN_EQ:
        helper = "sage_eq"
    if op_type == TOKEN_NEQ:
        helper = "sage_neq"
    if op_type == TOKEN_GT:
        helper = "sage_gt"
    if op_type == TOKEN_LT:
        helper = "sage_lt"
    if op_type == TOKEN_GTE:
        helper = "sage_gte"
    if op_type == TOKEN_LTE:
        helper = "sage_lte"
    if op_type == TOKEN_AMP:
        helper = "sage_bit_and"
    if op_type == TOKEN_PIPE:
        helper = "sage_bit_or"
    if op_type == TOKEN_CARET:
        helper = "sage_bit_xor"
    if op_type == TOKEN_LSHIFT:
        helper = "sage_lshift"
    if op_type == TOKEN_RSHIFT:
        helper = "sage_rshift"
    if op_type == TOKEN_AND:
        helper = "sage_and"
    if op_type == TOKEN_OR:
        helper = "sage_or"
    if helper == nil:
        cc.failed = true
        return "sage_nil()"
    return helper + "(" + left + ", " + right + ")"

proc cc_emit_dynamic_call(cc, call_expr):
    let cv = cc_emit_expr(cc, call_expr.callee)
    let argc = call_expr.arg_count
    let parts = []
    push(parts, "sage_call_function_value(")
    push(parts, cv)
    push(parts, ", " + str(argc))
    if argc == 0:
        push(parts, ", NULL)")
    else:
        push(parts, ", (SageValue[]){")
        for i in range(argc):
            if i > 0:
                push(parts, ", ")
            push(parts, cc_emit_expr(cc, call_expr.args[i]))
        push(parts, "})")
    return join(parts, "")

proc cc_emit_call_expr(cc, call_expr):
    let callee = call_expr.callee
    # Method call: obj.method(args)
    if callee.type == 12:
        # EXPR_GET
        let obj = cc_emit_expr(cc, callee.object)
        let method = callee.property.text
        if call_expr.arg_count == 0:
            return "sage_call_method(" + obj + ", " + DQ + method + DQ + ", 0, NULL)"
        let parts = []
        push(parts, "sage_call_method(")
        push(parts, obj)
        push(parts, ", " + DQ + method + DQ + ", ")
        push(parts, str(call_expr.arg_count))
        push(parts, ", (SageValue[]){")
        for i in range(call_expr.arg_count):
            if i > 0:
                push(parts, ", ")
            push(parts, cc_emit_expr(cc, call_expr.args[i]))
        push(parts, "})")
        return join(parts, "")
    if callee.type != 5:
        # Dynamic dispatch: the callee expression evaluates to a function
        # value (first-class functions).
        return cc_emit_dynamic_call(cc, call_expr)
    let name = callee.name.text
    let argc = call_expr.arg_count
    # Builtin dispatch
    if name == "str":
        if argc == 1:
            return "sage_str(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "len":
        if argc == 1:
            return "sage_len(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "push":
        if argc == 2:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            return "sage_push(" + a0 + ", " + a1 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "pop":
        if argc == 1:
            return "sage_pop(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "range":
        if argc == 1:
            return "sage_range1(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        if argc == 2:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            return "sage_range2(" + a0 + ", " + a1 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "tonumber":
        if argc == 1:
            return "sage_tonumber(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "dict_keys":
        if argc == 1:
            return "sage_dict_keys_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "dict_values":
        if argc == 1:
            return "sage_dict_values_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "dict_has":
        if argc == 2:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            return "sage_dict_has_fn(" + a0 + ", " + a1 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "dict_delete":
        if argc == 2:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            return "sage_dict_delete_fn(" + a0 + ", " + a1 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "upper":
        if argc == 1:
            return "sage_upper(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "lower":
        if argc == 1:
            return "sage_lower(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "strip":
        if argc == 1:
            return "sage_strip_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "split":
        if argc == 2:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            return "sage_split_fn(" + a0 + ", " + a1 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "join":
        if argc == 2:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            return "sage_join_fn(" + a0 + ", " + a1 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "replace":
        if argc == 3:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            let a2 = cc_emit_expr(cc, call_expr.args[2])
            return "sage_replace_fn(" + a0 + ", " + a1 + ", " + a2 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "mem_alloc":
        if argc == 1:
            return "sage_mem_alloc_v(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "mem_free":
        if argc == 1:
            return "sage_mem_free(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "mem_read":
        if argc == 3:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            let a2 = cc_emit_expr(cc, call_expr.args[2])
            return "sage_mem_read(" + a0 + ", " + a1 + ", " + a2 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "mem_write":
        if argc == 4:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            let a2 = cc_emit_expr(cc, call_expr.args[2])
            let a3 = cc_emit_expr(cc, call_expr.args[3])
            return "sage_mem_write(" + a0 + ", " + a1 + ", " + a2 + ", " + a3 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "mem_size":
        if argc == 1:
            return "sage_mem_size(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "struct_def":
        if argc == 1:
            return "sage_struct_def(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "struct_new":
        if argc == 1:
            return "sage_struct_new(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "struct_get":
        if argc == 3:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            let a2 = cc_emit_expr(cc, call_expr.args[2])
            return "sage_struct_get(" + a0 + ", " + a1 + ", " + a2 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "struct_set":
        if argc == 4:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            let a2 = cc_emit_expr(cc, call_expr.args[2])
            let a3 = cc_emit_expr(cc, call_expr.args[3])
            return "sage_struct_set(" + a0 + ", " + a1 + ", " + a2 + ", " + a3 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "struct_size":
        if argc == 1:
            return "sage_struct_size(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "clock":
        if argc == 0:
            return "sage_clock_fn()"
        cc.failed = true
        return "sage_nil()"
    if name == "input":
        if argc == 0:
            return "sage_input_fn(sage_nil())"
        if argc == 1:
            return "sage_input_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "slice":
        if argc == 3:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            let a2 = cc_emit_expr(cc, call_expr.args[2])
            return "sage_slice(" + a0 + ", " + a1 + ", " + a2 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "asm_arch":
        if argc == 0:
            return "sage_arch_fn()"
        cc.failed = true
        return "sage_nil()"
    if name == "type":
        if argc == 1:
            return "sage_type_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "indexof":
        if argc == 2:
            return "sage_indexof_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ", " + cc_emit_expr(cc, call_expr.args[1]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "next":
        if argc == 1:
            return "sage_generator_next(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "startswith":
        if argc == 2:
            return "sage_str_startswith(" + cc_emit_expr(cc, call_expr.args[0]) + ", " + cc_emit_expr(cc, call_expr.args[1]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "endswith":
        if argc == 2:
            return "sage_str_endswith(" + cc_emit_expr(cc, call_expr.args[0]) + ", " + cc_emit_expr(cc, call_expr.args[1]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "readfile":
        if argc == 1:
            return "sage_read_file_v(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "writefile":
        if argc == 2:
            return "sage_write_file_v(" + cc_emit_expr(cc, call_expr.args[0]) + ", " + cc_emit_expr(cc, call_expr.args[1]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "exec":
        if argc == 1:
            return "sage_sys_exec_v(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "getenv":
        if argc == 1:
            return "sage_nil()"
        cc.failed = true
        return "sage_nil()"
    if name == "exists":
        if argc == 1:
            return "sage_file_exists_v(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "args":
        if argc == 0:
            return "sage_args_v()"
        cc.failed = true
        return "sage_nil()"
    if name == "__sys_exec":
        if argc == 1:
            return "sage_sys_exec_v(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "chr":
        if argc == 1:
            return "sage_chr_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "ord":
        if argc == 1:
            return "sage_ord_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "contains":
        if argc == 2:
            let a0 = cc_emit_expr(cc, call_expr.args[0])
            let a1 = cc_emit_expr(cc, call_expr.args[1])
            return "sage_str_contains(" + a0 + ", " + a1 + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "chr":
        if argc == 1:
            return "sage_chr_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "ord":
        if argc == 1:
            return "sage_ord_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "int":
        if argc == 1:
            return "sage_int_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "bytes":
        if argc == 1:
            return "sage_bytes_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "bytes_set":
        if argc == 3:
            return "sage_bytes_set_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ", " + cc_emit_expr(cc, call_expr.args[1]) + ", " + cc_emit_expr(cc, call_expr.args[2]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "bytes_get":
        if argc == 2:
            return "sage_bytes_get_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ", " + cc_emit_expr(cc, call_expr.args[1]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "bytes_len":
        if argc == 1:
            return "sage_bytes_len_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "bytes_to_string":
        if argc == 1:
            return "sage_bytes_to_string_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
        cc.failed = true
        return "sage_nil()"
    if name == "bytes_push":
        if argc == 2:
            return "sage_bytes_push_fn(" + cc_emit_expr(cc, call_expr.args[0]) + ", " + cc_emit_expr(cc, call_expr.args[1]) + ")"
        cc.failed = true
        return "sage_nil()"
    # Class constructor
    let cls = find_class_info(cc.classes, name)
    if cls != nil:
        let parts = []
        push(parts, "sage_construct(" + DQ + cls["class_name"] + DQ + ", ")
        if cls["parent_name"] != nil:
            push(parts, DQ + cls["parent_name"] + DQ)
        if cls["parent_name"] == nil:
            push(parts, "NULL")
        push(parts, ", " + str(argc) + ", ")
        if argc == 0:
            push(parts, "NULL)")
        if argc > 0:
            push(parts, "(SageValue[]){")
            for i in range(argc):
                if i > 0:
                    push(parts, ", ")
                push(parts, cc_emit_expr(cc, call_expr.args[i]))
            push(parts, "})")
        return join(parts, "")
    # User-defined function call (direct, arity-guarded)
    let proc_entry = find_proc_entry(cc.procs, name)
    if proc_entry == nil:
        # Unknown name: maybe a slot holding a function value.
        return cc_emit_dynamic_call(cc, call_expr)
    # Compile-time arity guard mirroring the C host.
    let pcount_g = proc_entry["param_count"]
    let pdl_g = proc_entry["param_defaults"]
    let req_g = pcount_g
    let qi2 = 0
    while qi2 < pcount_g:
        if qi2 < len(pdl_g) and pdl_g[qi2] != nil:
            req_g = qi2
            break
        qi2 = qi2 + 1
    if argc < req_g or argc > pcount_g:
        return "(fprintf(stderr, " + DQ + "Runtime Error: Expected " + str(req_g) + " to " + str(pcount_g) + " arguments but got " + str(argc) + ".\\n" + DQ + "), sage_nil())"
    let parts = []
    push(parts, proc_entry["c_name"])
    push(parts, "(")
    let env_arg = ""
    if proc_entry["needs_cenv"] == true:
        let capf2 = fn_top_capturing_frame(cc)
        if capf2 != nil:
            env_arg = capf2["env_var"]
        else:
            env_arg = "NULL"
    if env_arg != "":
        push(parts, env_arg)
        if argc > 0:
            push(parts, ", ")
    for i in range(argc):
        if i > 0:
            push(parts, ", ")
        push(parts, cc_emit_expr(cc, call_expr.args[i]))
    # Fill missing trailing arguments from declared parameter defaults.
    let pcount = proc_entry["param_count"]
    let pdefaults = proc_entry["param_defaults"]
    let fi = argc
    while fi < pcount:
        if pdefaults == nil or fi >= len(pdefaults) or pdefaults[fi] == nil:
            break
        push(parts, ", ")
        push(parts, cc_emit_expr(cc, pdefaults[fi]))
        fi = fi + 1
    while fi < pcount:
        # No default available; keep arity correct with nil (runtime will
        # surface the same value the interpreter would have left unset).
        if fi > 0:
            push(parts, ", ")
        push(parts, "sage_nil()")
        fi = fi + 1
    push(parts, ")")
    return join(parts, "")

proc cc_emit_set_expr(cc, expr):
    if expr.object != nil:
        # Property assignment: obj.prop = value
        let obj = cc_emit_expr(cc, expr.object)
        let prop = expr.property.text
        let escaped = escape_c_string(prop)
        let val = cc_emit_expr(cc, expr.value)
        return "({SageValue _obj = " + obj + "; SageValue _val = " + val + "; sage_dict_set(_obj.as.dict, " + DQ + escaped + DQ + ", _val); _val;})"
    let name = expr.property.text
    let slot = resolve_slot_name(cc, name)
    if slot == nil:
        cc.failed = true
        return "sage_nil()"
    let val = cc_emit_expr(cc, expr.value)
    return "sage_assign_slot(&" + slot + ", " + DQ + name + DQ + ", " + val + ")"

proc cc_emit_expr(cc, expr):
    let t = expr.type
    if t == 0:
        # EXPR_NUMBER
        return "sage_number(" + str(expr.value) + ")"
    if t == 1:
        # EXPR_STRING
        let escaped = escape_c_string(expr.value)
        return "sage_string(" + DQ + escaped + DQ + ")"
    if t == 2:
        # EXPR_BOOL
        if expr.value:
            return "sage_bool(1)"
        return "sage_bool(0)"
    if t == 3:
        # EXPR_NIL
        return "sage_nil()"
    if t == 4:
        # EXPR_BINARY
        return cc_emit_binary_expr(cc, expr)
    if t == 5:
        # EXPR_VARIABLE
        let name = expr.name.text
        let slot = resolve_slot_name(cc, name)
        if slot == nil:
            # First-class reference to a named procedure.
            let pe = find_proc_entry(cc.procs, name)
            if pe != nil:
                if pe["needs_cenv"] == true:
                    let capv = fn_top_capturing_frame(cc)
                    if capv != nil:
                        return "sage_bind_closure(&sage_fnobj_" + pe["c_name"] + ", " + capv["env_var"] + ")"
                    return "sage_bind_closure(&sage_fnobj_" + pe["c_name"] + ", NULL)"
                return "sage_function_value(&sage_fnobj_" + pe["c_name"] + ")"
            # Unknown identifier: C-host behavior is a stderr diagnostic and
            # a nil value at each access site (execution continues).
            return "sage_load_undefined(" + DQ + escape_c_string(name) + DQ + ")"
            return "sage_nil()"
        return "sage_load_slot(&" + slot + ", " + DQ + name + DQ + ")"
    if t == 6:
        # EXPR_CALL
        return cc_emit_call_expr(cc, expr)
    if t == 7:
        # EXPR_ARRAY
        return cc_emit_array_expr(cc, expr)
    if t == 8:
        # EXPR_INDEX
        return cc_emit_index_expr(cc, expr)
    if t == 14:
        # EXPR_INDEX_SET
        let arr = cc_emit_expr(cc, expr.object)
        let idx = cc_emit_expr(cc, expr.index)
        let val = cc_emit_expr(cc, expr.value)
        return "sage_index_set(" + arr + ", " + idx + ", " + val + ")"
    if t == 11:
        # EXPR_SLICE
        return cc_emit_slice_expr(cc, expr)
    if t == 17:
        # EXPR_COMPTIME: fold by emitting the inner expression.
        return cc_emit_expr(cc, expr.expression)
    if t == 18:
        # EXPR_PROC (anonymous): hoist to a generated top-level function and
        # yield a first-class function value. Capture-free subset.
        #
        # Two-pass compilation: the discovery pass pre-binds every anonymous
        # function (deterministic traversal => stable order), letting this
        # second pass reference prototypes/objects emitted up front.
        let cap_frame = fn_top_capturing_frame(cc)
        if cc.prebind_active and len(cc.anon_fns) < len(cc.prebound_anons):
            push(cc.anon_fns, cc.prebound_anons[len(cc.anon_fns)])
            if cap_frame != nil:
                entry_needs_cenv(cc.anon_fns[len(cc.anon_fns) - 1])
                return "sage_bind_closure(&" + pb_fnobj_of(cc.anon_fns[len(cc.anon_fns) - 1]) + ", " + cap_frame["env_var"] + ")"
            return "sage_function_value(&" + cc.anon_fns[len(cc.anon_fns) - 1]["fnobj"] + ")"
        let uid = cc.next_unique_id
        cc.next_unique_id = cc.next_unique_id + 1
        let cname = "sage_anon_fn_" + str(uid)
        let objname = "sage_anon_obj_" + str(uid)
        let entry = {}
        entry["c_name"] = cname
        entry["fnobj"] = objname
        entry["label"] = "<anon>"
        entry["param_count"] = expr.param_count
        entry["params"] = expr.params
        entry["body"] = expr.body
        entry["emitted"] = false
        push(cc.anon_fns, entry)
        if cap_frame != nil:
            entry["needs_cenv"] = true
            let snap9 = []
            for fi12 in range(len(cc.fn_stack)):
                push(snap9, cc.fn_stack[fi12])
            entry["frames"] = snap9
            return "sage_bind_closure(&" + objname + ", " + cap_frame["env_var"] + ")"
        return "sage_function_value(&" + objname + ")"
    if t == 13:
        # EXPR_SET
        return cc_emit_set_expr(cc, expr)
    if t == 9:
        # EXPR_DICT
        return cc_emit_dict_expr(cc, expr)
    if t == 10:
        # EXPR_TUPLE
        return cc_emit_tuple_expr(cc, expr)
    if t == 12:
        # EXPR_GET - property access
        let obj = cc_emit_expr(cc, expr.object)
        let prop = expr.property.text
        let escaped = escape_c_string(prop)
        return "sage_index(" + obj + ", sage_string(" + DQ + escaped + DQ + "))"
    cc.failed = true
    return "sage_nil()"

# ============================================================================
# Statement Emission
# ============================================================================

proc cc_emit_stmt_list(cc, stmt):
    let current = stmt
    while current != nil:
        cc_emit_stmt(cc, current)
        if cc.failed:
            return
        current = current.next

proc cc_emit_embedded_block(cc, stmt):
    cc.indent = cc.indent + 1
    push(cc.defer_scopes, [])
    if stmt != nil and stmt.type == 104:
        # STMT_BLOCK
        cc_emit_stmt_list(cc, stmt.statements)
    if stmt != nil and stmt.type != 104:
        cc_emit_stmt_list(cc, stmt)
    # Flush this block's defers in LIFO order (scope exit).
    let scope = cc.defer_scopes[len(cc.defer_scopes) - 1]
    let si = len(scope) - 1
    while si >= 0:
        cc_emit_stmt(cc, scope[si])
        si = si - 1
    pop(cc.defer_scopes)
    if stmt == nil:
        # empty block
        let x = 0
    cc.indent = cc.indent - 1

proc cc_emit_stmt(cc, stmt):
    let t = stmt.type
    if t == 100:
        # STMT_PRINT
        let e = cc_emit_expr(cc, stmt.expression)
        cc_line(cc, "sage_print_ln(" + e + ");")
        return
    if t == 101:
        # STMT_EXPRESSION
        let e = cc_emit_expr(cc, stmt.expression)
        cc_line(cc, "(void)" + e + ";")
        return
    if t == 122:
        # STMT_COMPTIME: constants evaluate identically at run time for the
        # emitted subset; register body bindings as globals, then emit the
        # body as ordinary statements (body may be list or block).
        let cbody = stmt.body
        collect_global_lets(cc, cbody)
        if cbody != nil and cbody.type == 104:
            cc_emit_stmt_list(cc, cbody.statements)
            return
        let cur = cbody
        while cur != nil:
            cc_emit_stmt(cc, cur)
            cur = cur.next
        return
    if t == 102:
        # STMT_LET
        let name = stmt.name.text
        let slot = resolve_slot_name(cc, name)
        if slot == nil:
            cc.failed = true
            return
        let init_val = "sage_nil()"
        if stmt.initializer != nil:
            init_val = cc_emit_expr(cc, stmt.initializer)
        cc_line(cc, "sage_define_slot(&" + slot + ", " + init_val + ");")
        return
    if t == 103:
        # STMT_IF
        let cond = cc_emit_expr(cc, stmt.condition)
        cc_line(cc, "if (sage_truthy(" + cond + ")) {")
        cc_emit_embedded_block(cc, stmt.then_branch)
        cc_line(cc, "}")
        if stmt.else_branch != nil:
            cc_line(cc, "else {")
            cc_emit_embedded_block(cc, stmt.else_branch)
            cc_line(cc, "}")
        return
    if t == 104:
        # STMT_BLOCK
        cc_emit_stmt_list(cc, stmt.statements)
        return
    if t == 105:
        # STMT_WHILE
        let cond = cc_emit_expr(cc, stmt.condition)
        cc_line(cc, "while (sage_truthy(" + cond + ")) {")
        cc_emit_embedded_block(cc, stmt.body)
        cc_line(cc, "}")
        return
    if t == 116:
        # STMT_YIELD — inside a generator collector this pushes the yielded
        # value onto the results array. Outside generators it is skipped.
        if cc.gen_out_var != nil:
            let yv = "sage_nil()"
            if stmt.value != nil:
                yv = cc_emit_expr(cc, stmt.value)
            cc_line(cc, "sage_array_push_raw(" + cc.gen_out_var + ", " + yv + ");")
        return
    if t == 113:
        # STMT_DEFER: collect into the innermost block scope; the scope
        # flush (below) emits it LIFO at scope exit.
        push(cc.defer_scopes[len(cc.defer_scopes) - 1], stmt.statement)
        return
    if t == 108:
        # STMT_RETURN — run all active defers, innermost first. Do NOT pop
        # scopes here; each enclosing block's exit-flush owns its scope.
        if cc.gen_collector:
            let ei9 = len(cc.defer_scopes) - 1
            while ei9 >= 0:
                let sc9 = cc.defer_scopes[ei9]
                let di9 = len(sc9) - 1
                while di9 >= 0:
                    cc_emit_stmt(cc, sc9[di9])
                    di9 = di9 - 1
                ei9 = ei9 - 1
            cc_line(cc, "return;")
            return
        let si3 = len(cc.defer_scopes) - 1
        while si3 >= 0:
            let sc = cc.defer_scopes[si3]
            let dj3 = len(sc) - 1
            while dj3 >= 0:
                cc_emit_stmt(cc, sc[dj3])
                dj3 = dj3 - 1
            si3 = si3 - 1
        let ret_val = "sage_nil()"
        if stmt.value != nil:
            ret_val = cc_emit_expr(cc, stmt.value)
        cc_line(cc, "return " + ret_val + ";")
        return
    if t == 109:
        # STMT_BREAK — flush active defers innermost first (no pops).
        let sbi = len(cc.defer_scopes) - 1
        while sbi >= 0:
            let scb = cc.defer_scopes[sbi]
            let dbj = len(scb) - 1
            while dbj >= 0:
                cc_emit_stmt(cc, scb[dbj])
                dbj = dbj - 1
            sbi = sbi - 1
        cc_line(cc, "break;")
        return
    if t == 110:
        # STMT_CONTINUE — flush active defers innermost first (no pops).
        let sci = len(cc.defer_scopes) - 1
        while sci >= 0:
            let scc = cc.defer_scopes[sci]
            let dck = len(scc) - 1
            while dck >= 0:
                cc_emit_stmt(cc, scc[dck])
                dck = dck - 1
            sci = sci - 1
        cc_line(cc, "continue;")
        return
    if t == 106:
        # STMT_PROC - top-level defs are emitted by
        # emit_function_definitions. Nested named procedures are hoisted:
        # registered here for call resolution, defined via the deferred
        # hoisted-definition flush with the parent environment threaded
        # through as a hidden leading parameter.
        if len(cc.fn_stack) > 0:
            # Register now so later call sites in this body resolve directly.
            let child_entry = add_proc_entry(cc, stmt.name.text, stmt.param_count, stmt.param_defaults)
            child_entry["needs_cenv"] = true
            let disc = {"name": stmt.name.text}
            disc["param_count"] = stmt.param_count
            disc["param_defaults"] = stmt.param_defaults
            push(cc.discovered_nested, disc)
            let snap10 = []
            for fi15 in range(len(cc.fn_stack)):
                push(snap10, cc.fn_stack[fi15])
            let hf2 = {}
            hf2["kind"] = "named"
            hf2["stmt"] = stmt
            hf2["entry"] = child_entry
            hf2["frames"] = snap10
            push(cc.hoisted_defs, hf2)

    if t == 107:
        # STMT_FOR
        let iterable = cc_emit_expr(cc, stmt.iterable)
        let var_name = stmt.variable.text
        let slot = resolve_slot_name(cc, var_name)
        if slot == nil:
            cc.failed = true
            return
        let iter_var = make_unique_name(cc, "sage_iter", var_name)
        let idx_var = make_unique_name(cc, "sage_idx", var_name)
        cc_line(cc, "{")
        cc.indent = cc.indent + 1
        cc_line(cc, "SageValue " + iter_var + " = " + iterable + ";")
        cc_line(cc, "if (" + iter_var + ".type == SAGE_TAG_GENERATOR) {")
        cc.indent = cc.indent + 1
        cc_line(cc, "fprintf(stderr, " + DQ + "Runtime Error: for loop iterable must be an array, tuple, or dict." + (BS + "n") + DQ + ");")
        cc.indent = cc.indent - 1
        cc_line(cc, "} else if (" + iter_var + ".type == SAGE_TAG_ARRAY) {")
        cc.indent = cc.indent + 1
        cc_line(cc, "for (int " + idx_var + " = 0; " + idx_var + " < " + iter_var + ".as.array->count; " + idx_var + "++) {")
        cc.indent = cc.indent + 1
        cc_line(cc, "sage_define_slot(&" + slot + ", " + iter_var + ".as.array->elements[" + idx_var + "]);")
        cc_emit_embedded_block(cc, stmt.body)
        cc.indent = cc.indent - 1
        cc_line(cc, "}")
        cc.indent = cc.indent - 1
        cc_line(cc, "} else if (" + iter_var + ".type == SAGE_TAG_STRING) {")
        cc.indent = cc.indent + 1
        cc_line(cc, "int _len = (int)strlen(" + iter_var + ".as.string);")
        cc_line(cc, "for (int " + idx_var + " = 0; " + idx_var + " < _len; " + idx_var + "++) {")
        cc.indent = cc.indent + 1
        cc_line(cc, "char _ch[2] = {" + iter_var + ".as.string[" + idx_var + "], '" + BS + "0'};")
        cc_line(cc, "sage_define_slot(&" + slot + ", sage_string(sage_dup_string(_ch)));")
        cc_emit_embedded_block(cc, stmt.body)
        cc.indent = cc.indent - 1
        cc_line(cc, "}")
        cc.indent = cc.indent - 1
        cc_line(cc, "} else if (" + iter_var + ".type == SAGE_TAG_DICT) {")
        cc.indent = cc.indent + 1
        cc_line(cc, "for (int " + idx_var + " = 0; " + idx_var + " < " + iter_var + ".as.dict->count; " + idx_var + "++) {")
        cc.indent = cc.indent + 1
        cc_line(cc, "sage_define_slot(&" + slot + ", sage_string(sage_dup_string(" + iter_var + ".as.dict->keys[" + idx_var + "])));")
        cc_emit_embedded_block(cc, stmt.body)
        cc.indent = cc.indent - 1
        cc_line(cc, "}")
        cc.indent = cc.indent - 1
        cc_line(cc, "}")
        cc.indent = cc.indent - 1
        cc_line(cc, "}")
        return
    if t == 114:
        # STMT_TRY
        cc_line(cc, "{")
        cc.indent = cc.indent + 1
        cc_line(cc, "if (sage_try_depth >= SAGE_MAX_TRY_DEPTH) sage_fail(" + DQ + "Runtime Error: try nesting too deep (max 1024)" + DQ + ");")
        cc_line(cc, "int _caught = 0;")
        cc_line(cc, "sage_try_depth++;")
        cc_line(cc, "if (setjmp(sage_try_stack[sage_try_depth - 1]) == 0) {")
        cc_emit_embedded_block(cc, stmt.try_block)
        cc_line(cc, "} else {")
        cc.indent = cc.indent + 1
        cc_line(cc, "_caught = 1;")
        if stmt.catch_count > 0:
            let catch_var = stmt.catches[0].exception_var.text
            let catch_slot = resolve_slot_name(cc, catch_var)
            if catch_slot != nil:
                cc_line(cc, "sage_define_slot(&" + catch_slot + ", sage_exception_value);")
        cc.indent = cc.indent - 1
        cc_line(cc, "}")
        cc_line(cc, "sage_try_depth--;")
        if stmt.catch_count > 0:
            cc_line(cc, "if (_caught) {")
            cc_emit_embedded_block(cc, stmt.catches[0].body)
            cc_line(cc, "}")
        if stmt.finally_block != nil:
            cc_emit_embedded_block(cc, stmt.finally_block)
        cc.indent = cc.indent - 1
        cc_line(cc, "}")
        return
    if t == 115:
        # STMT_RAISE
        let exc = "sage_string(" + DQ + "exception" + DQ + ")"
        if stmt.exception != nil:
            exc = cc_emit_expr(cc, stmt.exception)
        cc_line(cc, "sage_raise(" + exc + ");")
        return
    if t == 112:
        # STMT_MATCH — mirrors the interpreter exactly: evaluate value once;
        # per case (in order) evaluate the pattern and compare; on equality,
        # an optional guard must also be truthy or checking continues with
        # later cases; first unguarded-equal (or guard-passing) case runs its
        # body and finishes; default runs only when nothing matched.
        let mv_name = make_unique_name(cc, "sage_match_val", "v")
        let done_name = make_unique_name(cc, "sage_match_done", "d")
        cc_line(cc, "{")
        cc.indent = cc.indent + 1
        cc_line(cc, "SageValue " + mv_name + " = " + cc_emit_expr(cc, stmt.value) + ";")
        cc_line(cc, "int " + done_name + " = 0;")
        let ci3 = 0
        while ci3 < len(stmt.cases):
            let clause = stmt.cases[ci3]
            cc_line(cc, "if (!" + done_name + " && sage_values_equal(" + mv_name + ", " + cc_emit_expr(cc, clause["pattern"]) + ")) {")
            cc.indent = cc.indent + 1
            if clause["guard"] != nil:
                cc_line(cc, "if (sage_truthy(" + cc_emit_expr(cc, clause["guard"]) + ")) {")
                cc.indent = cc.indent + 1
                cc_line(cc, done_name + " = 1;")
                cc_emit_embedded_block(cc, clause["body"])
                cc.indent = cc.indent - 1
                cc_line(cc, "}")
            else:
                cc_line(cc, done_name + " = 1;")
                cc_emit_embedded_block(cc, clause["body"])
            cc.indent = cc.indent - 1
            cc_line(cc, "}")
            ci3 = ci3 + 1
        if stmt.default_case != nil:
            cc_line(cc, "if (!" + done_name + ") {")
            cc.indent = cc.indent + 1
            cc_emit_embedded_block(cc, stmt.default_case)
            cc.indent = cc.indent - 1
            cc_line(cc, "}")
        cc.indent = cc.indent - 1
        cc_line(cc, "}")
        return
    if t == 111:
        # STMT_CLASS - handled at top level
        return
    if t == 117:
        # STMT_IMPORT - skip (module import not supported in self-hosted C backend)
        return

# ============================================================================
# Runtime Prelude
# ============================================================================

proc emit_runtime_prelude(cc):
    let o = cc.output
    # Include headers
    push(o, "#include <setjmp.h>" + NL)
    push(o, "#include <stdarg.h>" + NL)
    push(o, "#include <stdio.h>" + NL)
    push(o, "#include <stdlib.h>" + NL)
    push(o, "#include <string.h>" + NL)
    push(o, "#include <stdint.h>" + NL)
    push(o, "#include <math.h>" + NL)
    push(o, "#include <ctype.h>" + NL)
    push(o, NL)
    # Type definitions
    push(o, "typedef struct SageValue SageValue;" + NL)
    push(o, NL)
    push(o, "typedef struct {" + NL)
    push(o, "    int count;" + NL)
    push(o, "    int capacity;" + NL)
    push(o, "    SageValue* elements;" + NL)
    push(o, "} SageArray;" + NL)
    push(o, NL)
    push(o, "typedef struct {" + NL)
    push(o, "    char** keys;" + NL)
    push(o, "    SageValue* values;" + NL)
    push(o, "    int count;" + NL)
    push(o, "    int capacity;" + NL)
    push(o, "} SageDict;" + NL)
    push(o, NL)
    push(o, "typedef struct {" + NL)
    push(o, "    SageValue* elements;" + NL)
    push(o, "    int count;" + NL)
    push(o, "} SageTuple;" + NL)
    push(o, NL)
    push(o, "typedef enum {" + NL)
    push(o, "    SAGE_TAG_NIL," + NL)
    push(o, "    SAGE_TAG_NUMBER," + NL)
    push(o, "    SAGE_TAG_BOOL," + NL)
    push(o, "    SAGE_TAG_STRING," + NL)
    push(o, "    SAGE_TAG_ARRAY," + NL)
    push(o, "    SAGE_TAG_DICT," + NL)
    push(o, "    SAGE_TAG_TUPLE," + NL)
    push(o, "    SAGE_TAG_FUNCTION," + NL)
    push(o, "    SAGE_TAG_GENERATOR" + NL)
    push(o, "} SageTag;" + NL)
    push(o, NL)
    push(o, "typedef struct SageFunction SageFunction;" + NL)
    push(o, "struct SageValue {" + NL)
    push(o, "    SageTag type;" + NL)
    push(o, "    union {" + NL)
    push(o, "        double number;" + NL)
    push(o, "        int boolean;" + NL)
    push(o, "        const char* string;" + NL)
    push(o, "        SageArray* array;" + NL)
    push(o, "        SageDict* dict;" + NL)
    push(o, "        SageTuple* tuple;" + NL)
    push(o, "        SageFunction* function;" + NL)
    push(o, "        void* generator;" + NL)
    push(o, "    } as;" + NL)
    push(o, "};" + NL)
    push(o, NL)
    push(o, "#define SAGE_MAX_FN_ARGS 8" + NL)
    push(o, "struct SageFunction {" + NL)
    push(o, "    const char* name;" + NL)
    push(o, "    int param_count;" + NL)
    push(o, "    void* fn;" + NL)
    push(o, "    void* env;" + NL)
    push(o, "};" + NL)
    push(o, NL)
    push(o, "static SageValue sage_function_value(SageFunction* f) {" + NL)
    push(o, "    SageValue v; v.type = SAGE_TAG_FUNCTION; v.as.function = f; return v;" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_nil(void);" + NL)
    push(o, "static void sage_fail(const char* message);" + NL)
    push(o, "static SageValue sage_string(const char* value);" + NL)
    push(o, "static SageValue sage_bool(int value);" + NL)
    push(o, "static SageValue sage_number(double value);" + NL)
    push(o, "static SageValue sage_nil(void);" + NL)
    push(o, "static SageValue sage_str_startswith(SageValue hay, SageValue pre);" + NL)
    push(o, "static SageValue sage_str_endswith(SageValue hay, SageValue suf);" + NL)
    push(o, "static SageValue sage_number(double value);" + NL)
    push(o, "static SageValue sage_read_file_v(SageValue path) {" + NL)
    push(o, "    FILE* f = fopen(path.as.string, \"rb\");" + NL)
    push(o, "    if (!f) return sage_nil();" + NL)
    push(o, "    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);" + NL)
    push(o, "    char* buf = (char*)malloc(sz + 1);" + NL)
    push(o, "    size_t rd = fread(buf, 1, sz, f); fclose(f);" + NL)
    push(o, "    buf[rd] = 0;" + NL)
    push(o, "    return sage_string(buf);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_write_file_v(SageValue path, SageValue data) {" + NL)
    push(o, "    FILE* f = fopen(path.as.string, \"wb\");" + NL)
    push(o, "    if (!f) return sage_bool(0);" + NL)
    push(o, "    fwrite(data.as.string, 1, strlen(data.as.string), f); fclose(f);" + NL)
    push(o, "    return sage_bool(1);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_file_exists_v(SageValue path) {" + NL)
    push(o, "    FILE* f = fopen(path.as.string, \"rb\");" + NL)
    push(o, "    if (!f) return sage_bool(0);" + NL)
    push(o, "    fclose(f);" + NL)
    push(o, "    return sage_bool(1);" + NL)
    push(o, "}" + NL)



    push(o, "typedef struct SageGenerator SageGenerator;" + NL)
    push(o, "struct SageGenerator {" + NL)
    push(o, "    SageArray* items;" + NL)
    push(o, "    int index;" + NL)
    push(o, "};" + NL)
    push(o, "static SageValue sage_make_generator_from_array(SageArray* items) {" + NL)
    push(o, "    SageGenerator* g = (SageGenerator*)malloc(sizeof(SageGenerator));" + NL)
    push(o, "    if (g == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    g->items = items;" + NL)
    push(o, "    g->index = 0;" + NL)
    push(o, "    SageValue v; v.type = SAGE_TAG_GENERATOR; v.as.generator = g; return v;" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_generator_next(SageValue gv) {" + NL)
    push(o, "    if (gv.type != SAGE_TAG_GENERATOR) {" + NL)
    push(o, "        fprintf(stderr, \"Runtime Error: next() requires a generator.\\n\");" + NL)
    push(o, "        return sage_nil();" + NL)
    push(o, "    }" + NL)
    push(o, "    SageGenerator* g = (SageGenerator*)gv.as.generator;" + NL)
    push(o, "    if (g->index >= g->items->count) return sage_nil();" + NL)
    push(o, "    return g->items->elements[g->index++];" + NL)
    push(o, "}" + NL)

    push(o, "static SageValue sage_call_function_value(SageValue callee, int argc, SageValue* args) {" + NL)
    push(o, "    if (callee.type != SAGE_TAG_FUNCTION || callee.as.function == NULL) {" + NL)
    push(o, "        fprintf(stderr, \"Runtime Error: value is not callable.\\n\");" + NL)
    push(o, "        return sage_nil();" + NL)
    push(o, "    }" + NL)
    push(o, "    SageFunction* sf = callee.as.function;" + NL)
    push(o, "    if (argc != sf->param_count) {" + NL)
    push(o, "        fprintf(stderr, \"Runtime Error: Expected %d to %d arguments but got %d.\\n\", sf->param_count, sf->param_count, argc);" + NL)
    push(o, "        return sage_nil();" + NL)
    push(o, "    }" + NL)
    push(o, "    if (sf->env != NULL) {" + NL)
    push(o, "        switch (sf->param_count) {" + NL)
    push(o, "            case 0: return ((SageValue(*)(void*))sf->fn)(sf->env);" + NL)
    push(o, "            case 1: return ((SageValue(*)(void*, SageValue))sf->fn)(sf->env, args[0]);" + NL)
    push(o, "            case 2: return ((SageValue(*)(void*, SageValue, SageValue))sf->fn)(sf->env, args[0], args[1]);" + NL)
    push(o, "            case 3: { SageValue a3[3]; for (int i=0;i<3;i++) a3[i]=args[i]; return ((SageValue(*)(void*, SageValue, SageValue, SageValue))sf->fn)(sf->env, a3[0], a3[1], a3[2]); }" + NL)
    push(o, "            case 4: { SageValue a4[4]; for (int i=0;i<4;i++) a4[i]=args[i]; return ((SageValue(*)(void*, SageValue, SageValue, SageValue, SageValue))sf->fn)(sf->env, a4[0], a4[1], a4[2], a4[3]); }" + NL)
    push(o, "            default: return sage_nil();" + NL)
    push(o, "        }" + NL)
    push(o, "    }" + NL)
    push(o, "    switch (sf->param_count) {" + NL)
    push(o, "        case 0: return ((SageValue(*)(void))sf->fn)();" + NL)
    push(o, "        case 1: return ((SageValue(*)(SageValue))sf->fn)(args[0]);" + NL)
    push(o, "        case 2: return ((SageValue(*)(SageValue, SageValue))sf->fn)(args[0], args[1]);" + NL)
    push(o, "        case 3: { SageValue b3[3]; for (int i=0;i<3;i++) b3[i]=args[i]; return ((SageValue(*)(SageValue, SageValue, SageValue))sf->fn)(b3[0], b3[1], b3[2]); }" + NL)
    push(o, "        case 4: { SageValue b4[4]; for (int i=0;i<4;i++) b4[i]=args[i]; return ((SageValue(*)(SageValue, SageValue, SageValue, SageValue))sf->fn)(b4[0], b4[1], b4[2], b4[3]); }" + NL)
    push(o, "        default: return sage_nil();" + NL)
    push(o, "    }" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_bind_closure(SageFunction* proto, void* env) {" + NL)
    push(o, "    SageFunction* f = (SageFunction*)malloc(sizeof(SageFunction));" + NL)
    push(o, "    if (f == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    f->name = proto->name; f->param_count = proto->param_count;" + NL)
    push(o, "    f->fn = proto->fn; f->env = env;" + NL)
    push(o, "    SageValue v; v.type = SAGE_TAG_FUNCTION; v.as.function = f; return v;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "typedef struct {" + NL)
    push(o, "    int defined;" + NL)
    push(o, "    SageValue value;" + NL)
    push(o, "} SageSlot;" + NL)
    push(o, NL)
    # Exception handling
    push(o, "#define SAGE_MAX_TRY_DEPTH 1024" + NL)
    push(o, "static jmp_buf sage_try_stack[SAGE_MAX_TRY_DEPTH];" + NL)
    push(o, "static SageValue sage_exception_value;" + NL)
    push(o, "static int sage_try_depth = 0;" + NL)
    push(o, NL)
    # Utility functions
    let bsn = BS + "n"
    let bsq = BS + DQ
    let bs0 = BS + "0"
    push(o, "static void sage_fail(const char* message) {" + NL)
    push(o, "    fputs(message, stderr);" + NL)
    push(o, "    fputc('" + bsn + "', stderr);" + NL)
    push(o, "    exit(1);" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static char* sage_dup_string(const char* text) {" + NL)
    push(o, "    size_t len = strlen(text);" + NL)
    push(o, "    char* copy = (char*)malloc(len + 1);" + NL)
    push(o, "    if (copy == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    memcpy(copy, text, len + 1);" + NL)
    push(o, "    return copy;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageArray* sage_new_array(void) {" + NL)
    push(o, "    SageArray* array = (SageArray*)malloc(sizeof(SageArray));" + NL)
    push(o, "    if (array == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    array->count = 0;" + NL)
    push(o, "    array->capacity = 0;" + NL)
    push(o, "    array->elements = NULL;" + NL)
    push(o, "    return array;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Value constructors
    push(o, "static SageValue sage_nil(void) { SageValue v; v.type = SAGE_TAG_NIL; v.as.number = 0; return v; }" + NL)
    push(o, "static SageValue sage_number(double value) { SageValue v; v.type = SAGE_TAG_NUMBER; v.as.number = value; return v; }" + NL)
    push(o, "static SageValue sage_bool(int value) { SageValue v; v.type = SAGE_TAG_BOOL; v.as.boolean = value ? 1 : 0; return v; }" + NL)
    push(o, "static SageValue sage_string(const char* value) { SageValue v; v.type = SAGE_TAG_STRING; v.as.string = value; return v; }" + NL)
    push(o, "static SageValue sage_array(void) { SageValue v; v.type = SAGE_TAG_ARRAY; v.as.array = sage_new_array(); return v; }" + NL)
    push(o, "static SageSlot sage_slot_undefined(void) { SageSlot slot; slot.defined = 0; slot.value = sage_nil(); return slot; }" + NL)
    push(o, NL)
    # Dict
    push(o, "static SageValue sage_make_dict(void) {" + NL)
    push(o, "    SageDict* dict = (SageDict*)malloc(sizeof(SageDict));" + NL)
    push(o, "    if (dict == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    dict->capacity = 16;" + NL)
    push(o, "    dict->keys = (char**)calloc(dict->capacity, sizeof(char*));" + NL)
    push(o, "    dict->values = (SageValue*)calloc(dict->capacity, sizeof(SageValue));" + NL)
    push(o, "    dict->count = 0;" + NL)
    push(o, "    SageValue v; v.type = SAGE_TAG_DICT; v.as.dict = dict;" + NL)
    push(o, "    return v;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static void sage_dict_set(SageDict* dict, const char* key, SageValue value) {" + NL)
    push(o, "    for (int i = 0; i < dict->count; i++) {" + NL)
    push(o, "        if (strcmp(dict->keys[i], key) == 0) {" + NL)
    push(o, "            dict->values[i] = value;" + NL)
    push(o, "            return;" + NL)
    push(o, "        }" + NL)
    push(o, "    }" + NL)
    push(o, "    if (dict->count >= dict->capacity) {" + NL)
    push(o, "        int cap = dict->capacity == 0 ? 4 : dict->capacity * 2;" + NL)
    push(o, "        dict->keys = (char**)realloc(dict->keys, sizeof(char*) * (size_t)cap);" + NL)
    push(o, "        dict->values = (SageValue*)realloc(dict->values, sizeof(SageValue) * (size_t)cap);" + NL)
    push(o, "        if (dict->keys == NULL || dict->values == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "        dict->capacity = cap;" + NL)
    push(o, "    }" + NL)
    push(o, "    dict->keys[dict->count] = sage_dup_string(key);" + NL)
    push(o, "    dict->values[dict->count] = value;" + NL)
    push(o, "    dict->count++;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_dict_get(SageDict* dict, const char* key) {" + NL)
    push(o, "    for (int i = 0; i < dict->count; i++) {" + NL)
    push(o, "        if (strcmp(dict->keys[i], key) == 0) return dict->values[i];" + NL)
    push(o, "    }" + NL)
    push(o, "    return sage_nil();" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Tuple
    push(o, "static SageValue sage_make_tuple(int count, const SageValue* values) {" + NL)
    push(o, "    SageTuple* tuple = (SageTuple*)malloc(sizeof(SageTuple));" + NL)
    push(o, "    if (tuple == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    tuple->count = count;" + NL)
    push(o, "    tuple->elements = (SageValue*)malloc(sizeof(SageValue) * (size_t)count);" + NL)
    push(o, "    if (tuple->elements == NULL && count > 0) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    for (int i = 0; i < count; i++) tuple->elements[i] = values[i];" + NL)
    push(o, "    SageValue v; v.type = SAGE_TAG_TUPLE; v.as.tuple = tuple;" + NL)
    push(o, "    return v;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Raise
    push(o, "static void sage_raise(SageValue value) {" + NL)
    push(o, "    if (sage_try_depth > 0) {" + NL)
    push(o, "        sage_exception_value = value;" + NL)
    push(o, "        longjmp(sage_try_stack[sage_try_depth - 1], 1);" + NL)
    push(o, "    }" + NL)
    push(o, "    fputs(" + DQ + "Unhandled exception: " + DQ + ", stderr);" + NL)
    push(o, "    if (value.type == SAGE_TAG_STRING) fputs(value.as.string, stderr);" + NL)
    push(o, "    else fputs(" + DQ + "(unknown)" + DQ + ", stderr);" + NL)
    push(o, "    fputc('" + bsn + "', stderr);" + NL)
    push(o, "    exit(1);" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Array helpers
    push(o, "static void sage_array_reserve(SageArray* array, int needed) {" + NL)
    push(o, "    if (array->capacity >= needed) return;" + NL)
    push(o, "    int capacity = array->capacity == 0 ? 4 : array->capacity;" + NL)
    push(o, "    while (capacity < needed) capacity *= 2;" + NL)
    push(o, "    SageValue* elements = (SageValue*)realloc(array->elements, sizeof(SageValue) * (size_t)capacity);" + NL)
    push(o, "    if (elements == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    array->elements = elements;" + NL)
    push(o, "    array->capacity = capacity;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static void sage_array_push_raw(SageArray* array, SageValue value) {" + NL)
    push(o, "    sage_array_reserve(array, array->count + 1);" + NL)
    push(o, "    array->elements[array->count++] = value;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_make_array(int count, const SageValue* values) {" + NL)
    push(o, "    SageValue array = sage_array();" + NL)
    push(o, "    for (int i = 0; i < count; i++) {" + NL)
    push(o, "        sage_array_push_raw(array.as.array, values[i]);" + NL)
    push(o, "    }" + NL)
    push(o, "    return array;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Truthy, slot ops
    push(o, "static int sage_truthy(SageValue value) {" + NL)
    push(o, "    if (value.type == SAGE_TAG_NIL) return 0;" + NL)
    push(o, "    if (value.type == SAGE_TAG_BOOL) return value.as.boolean;" + NL)
    push(o, "    return 1;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_load_undefined(const char* name) {" + NL)
    push(o, "        fprintf(stderr, " + DQ + "Runtime Error: Undefined variable '%s'." + bsn + DQ + ", name);" + NL)
    push(o, "        return sage_nil();" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_load_slot(const SageSlot* slot, const char* name) {" + NL)
    push(o, "    if (!slot->defined) {" + NL)
    push(o, "        fprintf(stderr, " + DQ + "Runtime Error: Undefined variable '%s'." + bsn + DQ + ", name);" + NL)
    push(o, "        return sage_nil();" + NL)
    push(o, "    }" + NL)
    push(o, "    return slot->value;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static void sage_define_slot(SageSlot* slot, SageValue value) {" + NL)
    push(o, "    slot->defined = 1;" + NL)
    push(o, "    slot->value = value;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_assign_slot(SageSlot* slot, const char* name, SageValue value) {" + NL)
    push(o, "    if (!slot->defined) {" + NL)
    push(o, "        fprintf(stderr, " + DQ + "Runtime Error: Undefined variable '%s'." + bsn + DQ + ", name);" + NL)
    push(o, "        return sage_nil();" + NL)
    push(o, "    }" + NL)
    push(o, "    slot->value = value;" + NL)
    push(o, "    return value;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Values equal
    push(o, "static int sage_values_equal(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != right.type) return 0;" + NL)
    push(o, "    switch (left.type) {" + NL)
    push(o, "        case SAGE_TAG_NIL: return 1;" + NL)
    push(o, "        case SAGE_TAG_NUMBER: return left.as.number == right.as.number;" + NL)
    push(o, "        case SAGE_TAG_BOOL: return left.as.boolean == right.as.boolean;" + NL)
    push(o, "        case SAGE_TAG_STRING: return strcmp(left.as.string, right.as.string) == 0;" + NL)
    push(o, "        case SAGE_TAG_ARRAY: return left.as.array == right.as.array;" + NL)
    push(o, "        case SAGE_TAG_DICT: return left.as.dict == right.as.dict;" + NL)
    push(o, "        case SAGE_TAG_TUPLE: return left.as.tuple == right.as.tuple;" + NL)
    push(o, "    }" + NL)
    push(o, "    return 0;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Print
    push(o, "static void sage_print_value(SageValue value) {" + NL)
    push(o, "    switch (value.type) {" + NL)
    push(o, "        case SAGE_TAG_NUMBER: printf(" + DQ + "%g" + DQ + ", value.as.number); break;" + NL)
    push(o, "        case SAGE_TAG_BOOL: fputs(value.as.boolean ? " + DQ + "true" + DQ + " : " + DQ + "false" + DQ + ", stdout); break;" + NL)
    push(o, "        case SAGE_TAG_STRING: fputs(value.as.string, stdout); break;" + NL)
    push(o, "        case SAGE_TAG_ARRAY:" + NL)
    push(o, "            fputc('[', stdout);" + NL)
    push(o, "            for (int i = 0; i < value.as.array->count; i++) {" + NL)
    push(o, "                if (i > 0) fputs(" + DQ + ", " + DQ + ", stdout);" + NL)
    push(o, "                sage_print_value(value.as.array->elements[i]);" + NL)
    push(o, "            }" + NL)
    push(o, "            fputc(']', stdout);" + NL)
    push(o, "            break;" + NL)
    push(o, "        case SAGE_TAG_DICT:" + NL)
    push(o, "            fputc('{', stdout);" + NL)
    push(o, "            for (int i = 0; i < value.as.dict->count; i++) {" + NL)
    push(o, "                if (i > 0) fputs(" + DQ + ", " + DQ + ", stdout);" + NL)
    push(o, "                printf(" + DQ + bsq + "%s" + bsq + ": " + DQ + ", value.as.dict->keys[i]);" + NL)
    push(o, "                sage_print_value(value.as.dict->values[i]);" + NL)
    push(o, "            }" + NL)
    push(o, "            fputc('}', stdout);" + NL)
    push(o, "            break;" + NL)
    push(o, "        case SAGE_TAG_TUPLE:" + NL)
    push(o, "            fputc('(', stdout);" + NL)
    push(o, "            for (int i = 0; i < value.as.tuple->count; i++) {" + NL)
    push(o, "                if (i > 0) fputs(" + DQ + ", " + DQ + ", stdout);" + NL)
    push(o, "                sage_print_value(value.as.tuple->elements[i]);" + NL)
    push(o, "            }" + NL)
    push(o, "            fputc(')', stdout);" + NL)
    push(o, "            break;" + NL)
    push(o, "        case SAGE_TAG_NIL: fputs(" + DQ + "nil" + DQ + ", stdout); break;" + NL)
    push(o, "    }" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static void sage_print_ln(SageValue value) {" + NL)
    push(o, "    sage_print_value(value);" + NL)
    push(o, "    fputc('" + bsn + "', stdout);" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # str()
    push(o, "static SageValue sage_str(SageValue value) {" + NL)
    push(o, "    char buffer[64];" + NL)
    push(o, "    switch (value.type) {" + NL)
    push(o, "        case SAGE_TAG_STRING: return value;" + NL)
    push(o, "        case SAGE_TAG_NUMBER:" + NL)
    push(o, "            snprintf(buffer, sizeof(buffer), " + DQ + "%g" + DQ + ", value.as.number);" + NL)
    push(o, "            return sage_string(sage_dup_string(buffer));" + NL)
    push(o, "        case SAGE_TAG_BOOL:" + NL)
    push(o, "            return sage_string(value.as.boolean ? " + DQ + "true" + DQ + " : " + DQ + "false" + DQ + ");" + NL)
    push(o, "        case SAGE_TAG_NIL:" + NL)
    push(o, "            return sage_string(" + DQ + "nil" + DQ + ");" + NL)
    push(o, "        case SAGE_TAG_ARRAY:" + NL)
    push(o, "            return sage_string(" + DQ + "<array>" + DQ + ");" + NL)
    push(o, "        case SAGE_TAG_DICT:" + NL)
    push(o, "            return sage_string(" + DQ + "<dict>" + DQ + ");" + NL)
    push(o, "        case SAGE_TAG_TUPLE:" + NL)
    push(o, "            return sage_string(" + DQ + "<tuple>" + DQ + ");" + NL)
    push(o, "    }" + NL)
    push(o, "    return sage_string(" + DQ + "nil" + DQ + ");" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # len, index, slice, push, pop
    push(o, "static SageValue sage_len(SageValue value) {" + NL)
    push(o, "    if (value.type == SAGE_TAG_STRING) return sage_number((double)strlen(value.as.string));" + NL)
    push(o, "    if (value.type == SAGE_TAG_ARRAY) return sage_number((double)value.as.array->count);" + NL)
    push(o, "    if (value.type == SAGE_TAG_DICT) return sage_number((double)value.as.dict->count);" + NL)
    push(o, "    if (value.type == SAGE_TAG_TUPLE) return sage_number((double)value.as.tuple->count);" + NL)
    push(o, "    return sage_nil();" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_index(SageValue collection, SageValue index) {" + NL)
    push(o, "    if (collection.type == SAGE_TAG_ARRAY && index.type == SAGE_TAG_NUMBER) {" + NL)
    push(o, "        int idx = (int)index.as.number;" + NL)
    push(o, "        if (idx < 0 || idx >= collection.as.array->count) return sage_nil();" + NL)
    push(o, "        return collection.as.array->elements[idx];" + NL)
    push(o, "    }" + NL)
    push(o, "    if (collection.type == SAGE_TAG_DICT && index.type == SAGE_TAG_STRING) {" + NL)
    push(o, "        return sage_dict_get(collection.as.dict, index.as.string);" + NL)
    push(o, "    }" + NL)
    push(o, "    if (collection.type == SAGE_TAG_TUPLE && index.type == SAGE_TAG_NUMBER) {" + NL)
    push(o, "        int idx = (int)index.as.number;" + NL)
    push(o, "        if (idx < 0 || idx >= collection.as.tuple->count) return sage_nil();" + NL)
    push(o, "        return collection.as.tuple->elements[idx];" + NL)
    push(o, "    }" + NL)
    push(o, "    if (collection.type == SAGE_TAG_STRING && index.type == SAGE_TAG_NUMBER) {" + NL)
    push(o, "        int idx = (int)index.as.number;" + NL)
    push(o, "        int len = (int)strlen(collection.as.string);" + NL)
    push(o, "        if (idx < 0) idx = len + idx;" + NL)
    push(o, "        if (idx < 0 || idx >= len) return sage_nil();" + NL)
    push(o, "        char buf[2] = {collection.as.string[idx], '" + bs0 + "'};" + NL)
    push(o, "        return sage_string(sage_dup_string(buf));" + NL)
    push(o, "    }" + NL)
    push(o, "    return sage_nil();" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_index_set(SageValue collection, SageValue index, SageValue value) {" + NL)
    push(o, "    if (collection.type == SAGE_TAG_ARRAY && index.type == SAGE_TAG_NUMBER) {" + NL)
    push(o, "        int idx = (int)index.as.number;" + NL)
    push(o, "        if (idx >= 0 && idx < collection.as.array->count) collection.as.array->elements[idx] = value;" + NL)
    push(o, "    }" + NL)
    push(o, "    if (collection.type == SAGE_TAG_DICT && index.type == SAGE_TAG_STRING) {" + NL)
    push(o, "        sage_dict_set(collection.as.dict, index.as.string, value);" + NL)
    push(o, "    }" + NL)
    push(o, "    return value;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # slice, push, pop, range
    push(o, "static SageValue sage_slice(SageValue array, SageValue start, SageValue end) {" + NL)
    push(o, "    if (array.type == SAGE_TAG_STRING) {" + NL)
    push(o, "        int len = (int)strlen(array.as.string);" + NL)
    push(o, "        int sIdx = (start.type == SAGE_TAG_NUMBER) ? (int)start.as.number : 0;" + NL)
    push(o, "        int eIdx = (end.type == SAGE_TAG_NUMBER) ? (int)end.as.number : len;" + NL)
    push(o, "        if (sIdx < 0) sIdx = len + sIdx;" + NL)
    push(o, "        if (eIdx < 0) eIdx = len + eIdx;" + NL)
    push(o, "        if (sIdx < 0) sIdx = 0;" + NL)
    push(o, "        if (eIdx > len) eIdx = len;" + NL)
    push(o, "        if (sIdx >= eIdx) return sage_string(sage_dup_string(\"\"));" + NL)
    push(o, "        char* result = (char*)malloc((size_t)(eIdx - sIdx) + 1);" + NL)
    push(o, "        memcpy(result, array.as.string + sIdx, (size_t)(eIdx - sIdx));" + NL)
    push(o, "        result[eIdx - sIdx] = '\\0';" + NL)
    push(o, "        return sage_string(result);" + NL)
    push(o, "    }" + NL)
    push(o, "    if (array.type != SAGE_TAG_ARRAY) return sage_nil();" + NL)
    push(o, "    int start_index = 0;" + NL)
    push(o, "    int end_index = array.as.array->count;" + NL)
    push(o, "    if (start.type == SAGE_TAG_NUMBER) start_index = (int)start.as.number;" + NL)
    push(o, "    if (end.type == SAGE_TAG_NUMBER) end_index = (int)end.as.number;" + NL)
    push(o, "    if (start_index < 0) start_index = array.as.array->count + start_index;" + NL)
    push(o, "    if (end_index < 0) end_index = array.as.array->count + end_index;" + NL)
    push(o, "    if (start_index < 0) start_index = 0;" + NL)
    push(o, "    if (end_index > array.as.array->count) end_index = array.as.array->count;" + NL)
    push(o, "    if (start_index >= end_index) return sage_array();" + NL)
    push(o, "    SageValue result = sage_array();" + NL)
    push(o, "    for (int i = start_index; i < end_index; i++) {" + NL)
    push(o, "        sage_array_push_raw(result.as.array, array.as.array->elements[i]);" + NL)
    push(o, "    }" + NL)
    push(o, "    return result;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_push(SageValue array, SageValue value) {" + NL)
    push(o, "    if (array.type != SAGE_TAG_ARRAY) return sage_nil();" + NL)
    push(o, "    sage_array_push_raw(array.as.array, value);" + NL)
    push(o, "    return sage_nil();" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_pop(SageValue array) {" + NL)
    push(o, "    if (array.type != SAGE_TAG_ARRAY || array.as.array->count == 0) return sage_nil();" + NL)
    push(o, "    return array.as.array->elements[--array.as.array->count];" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_range2(SageValue start, SageValue end) {" + NL)
    push(o, "    if (start.type != SAGE_TAG_NUMBER || end.type != SAGE_TAG_NUMBER) return sage_nil();" + NL)
    push(o, "    SageValue result = sage_array();" + NL)
    push(o, "    for (int i = (int)start.as.number; i < (int)end.as.number; i++) {" + NL)
    push(o, "        sage_array_push_raw(result.as.array, sage_number((double)i));" + NL)
    push(o, "    }" + NL)
    push(o, "    return result;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_range1(SageValue end) {" + NL)
    push(o, "    return sage_range2(sage_number(0), end);" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Arithmetic and comparison operators

    push(o, "static const char* sage_type_name_of(SageValue v) {" + NL)
    push(o, "    switch (v.type) {" + NL)
    push(o, "        case SAGE_TAG_NIL: return \"nil\";" + NL)
    push(o, "        case SAGE_TAG_BOOL: return \"bool\";" + NL)
    push(o, "        case SAGE_TAG_NUMBER: return \"number\";" + NL)
    push(o, "        case SAGE_TAG_STRING: return \"string\";" + NL)
    push(o, "        case SAGE_TAG_ARRAY: return \"array\";" + NL)
    push(o, "        case SAGE_TAG_DICT: return \"dict\";" + NL)
    push(o, "        case SAGE_TAG_TUPLE: return \"tuple\";" + NL)
    push(o, "        default: return \"unknown\";" + NL)
    push(o, "    }" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_type_fn(SageValue v) { return sage_string(sage_dup_string(sage_type_name_of(v))); }" + NL)
    push(o, "static SageValue sage_indexof_fn(SageValue hay, SageValue needle) {" + NL)
    push(o, "    if (hay.type != SAGE_TAG_STRING || needle.type != SAGE_TAG_STRING) return sage_number(-1);" + NL)
    push(o, "    const char* pos = strstr(hay.as.string, needle.as.string);" + NL)
    push(o, "    if (pos == NULL) return sage_number(-1);" + NL)
    push(o, "    return sage_number((double)(pos - hay.as.string));" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_str_contains(SageValue hay, SageValue needle) {" + NL)
    push(o, "    if (hay.type != SAGE_TAG_STRING || needle.type != SAGE_TAG_STRING) return sage_bool(0);" + NL)
    push(o, "    return sage_bool(strstr(hay.as.string, needle.as.string) != NULL);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_chr_fn(SageValue code) {" + NL)
    push(o, "    char buf[2] = { (char)((int)code.as.number), '\\0' };" + NL)
    push(o, "    return sage_string(sage_dup_string(buf));" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_ord_fn(SageValue s) {" + NL)
    push(o, "    if (s.type != SAGE_TAG_STRING || strlen(s.as.string) == 0) return sage_nil();" + NL)
    push(o, "    return sage_number((double)(unsigned char)s.as.string[0]);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_int_fn(SageValue v) {" + NL)
    push(o, "    if (v.type == SAGE_TAG_NUMBER) return sage_number((double)(long long)v.as.number);" + NL)
    push(o, "    if (v.type == SAGE_TAG_STRING) return sage_number((double)strtoll(v.as.string, NULL, 10));" + NL)
    push(o, "    return sage_number(0);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_bytes_fn(SageValue n) {" + NL)
    push(o, "    int count = (int)n.as.number;" + NL)
    push(o, "    SageValue out = sage_array();" + NL)
    push(o, "    sage_array_reserve(out.as.array, count < 0 ? 0 : count);" + NL)
    push(o, "    for (int i = 0; i < count; i++) sage_array_push_raw(out.as.array, sage_number(0));" + NL)
    push(o, "    return out;" + NL)
    push(o, "}" + NL)
    push(o, "static void sage_bytes_set_fn(SageValue b, SageValue i, SageValue v) { sage_index_set(b, i, v); }" + NL)
    push(o, "static SageValue sage_bytes_get_fn(SageValue b, SageValue i) { return sage_index(b, i); }" + NL)
    push(o, "static SageValue sage_bytes_len_fn(SageValue b) { return sage_len(b); }" + NL)
    push(o, "static SageValue sage_bytes_to_string_fn(SageValue b) {" + NL)
    push(o, "    if (b.type != SAGE_TAG_ARRAY) return sage_string(sage_dup_string(\"\"));" + NL)
    push(o, "    int n = b.as.array->count;" + NL)
    push(o, "    char* result = (char*)malloc((size_t)n + 1);" + NL)
    push(o, "    for (int i = 0; i < n; i++) result[i] = (char)(int)b.as.array->elements[i].as.number;" + NL)
    push(o, "    result[n] = '\\0';" + NL)
    push(o, "    return sage_string(result);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_bytes_push_fn(SageValue b, SageValue v) { sage_array_push_raw(b.as.array, v); return b; }" + NL)
    push(o, "static SageValue sage_str_startswith(SageValue hay, SageValue pre) {" + NL)
    push(o, "    if (hay.type != SAGE_TAG_STRING || pre.type != SAGE_TAG_STRING) return sage_bool(0);" + NL)
    push(o, "    return sage_bool(strncmp(hay.as.string, pre.as.string, strlen(pre.as.string)) == 0);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_str_endswith(SageValue hay, SageValue suf) {" + NL)
    push(o, "    if (hay.type != SAGE_TAG_STRING || suf.type != SAGE_TAG_STRING) return sage_bool(0);" + NL)
    push(o, "    size_t hl = strlen(hay.as.string), sl = strlen(suf.as.string);" + NL)
    push(o, "    if (sl > hl) return sage_bool(0);" + NL)
    push(o, "    return sage_bool(strcmp(hay.as.string + hl - sl, suf.as.string) == 0);" + NL)
    push(o, "}" + NL)
    push(o, "static int sage_is_safe_command(const char* cmd) {" + NL)
    push(o, "    if (!cmd) return 0;" + NL)
    push(o, "    while (*cmd && isspace((unsigned char)*cmd)) cmd++;" + NL)
    push(o, "    if (cmd[0] == '-') return 0;" + NL)
    push(o, "    for (const char* p = cmd; *p; p++) {" + NL)
    push(o, "        if (!isalnum((unsigned char)*p) && *p != '/' && *p != '.' &&" + NL)
    push(o, "            *p != '-' && *p != '_' && *p != '~' && *p != ' ' && *p != '\\'') {" + NL)
    push(o, "            return 0;" + NL)
    push(o, "        }" + NL)
    push(o, "    }" + NL)
    push(o, "    return 1;" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_sys_exec_v(SageValue cmd) {" + NL)
    push(o, "    if (cmd.type != SAGE_TAG_STRING) return sage_number(-1);" + NL)
    push(o, "    if (!sage_is_safe_command(cmd.as.string)) {" + NL)
    push(o, "        fprintf(stderr, \"Security Error: Unsafe characters in command\\n\");" + NL)
    push(o, "        return sage_number(-1);" + NL)
    push(o, "    }" + NL)
    push(o, "    int rc = system(cmd.as.string);" + NL)
    push(o, "    return sage_number((double)rc);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_mem_alloc_v(SageValue size) {" + NL)
    push(o, "    size_t n = (size_t)(long long)size.as.number;" + NL)
    push(o, "    unsigned char* base = (unsigned char*)malloc(n + 16);" + NL)
    push(o, "    if (base == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    *(size_t*)base = n;" + NL)
    push(o, "    return sage_number((double)(uintptr_t)(base + 16));" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_mem_free(SageValue p) {" + NL)
    push(o, "    free((unsigned char*)(uintptr_t)p.as.number - 16);" + NL)
    push(o, "    return sage_nil();" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_mem_read(SageValue a, SageValue o, SageValue s) {" + NL)
    push(o, "    if (a.type != SAGE_TAG_NUMBER || o.type != SAGE_TAG_NUMBER || s.type != SAGE_TAG_NUMBER) return sage_nil();" + NL)
    push(o, "    unsigned char* base = (unsigned char*)(uintptr_t)a.as.number - 16;" + NL)
    push(o, "    size_t cap = *(size_t*)base;" + NL)
    push(o, "    size_t off = (size_t)(long long)o.as.number;" + NL)
    push(o, "    size_t len = (size_t)(long long)s.as.number;" + NL)
    push(o, "    if (off + len > cap) return sage_nil();" + NL)
    push(o, "    unsigned long long v = 0; memcpy(&v, base + 16 + off, len);" + NL)
    push(o, "    return sage_number((double)v);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_mem_write(SageValue a, SageValue o, SageValue sz, SageValue v) {" + NL)
    push(o, "    unsigned char* base = (unsigned char*)(uintptr_t)a.as.number - 16;" + NL)
    push(o, "    size_t cap = *(size_t*)base;" + NL)
    push(o, "    size_t off = (size_t)(long long)o.as.number;" + NL)
    push(o, "    size_t wr = (size_t)(long long)sz.as.number; if (off + wr > cap) wr = cap - off;" + NL)
    push(o, "    unsigned long long val = (unsigned long long)v.as.number;" + NL)
    push(o, "    memcpy(base + 16 + off, &val, wr);" + NL)
    push(o, "    return v;" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_mem_size(SageValue p) {" + NL)
    push(o, "    unsigned char* base = (unsigned char*)(uintptr_t)p.as.number - 16;" + NL)
    push(o, "    return sage_number((double)*(size_t*)base);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_struct_new(SageValue defv) { (void)defv; return sage_make_dict(); }" + NL)
    push(o, "static SageValue sage_struct_def(SageValue v) { (void)v; return sage_make_dict(); }" + NL)
    push(o, "static SageValue sage_struct_size(SageValue v) { (void)v; return sage_number(0); }" + NL)
    push(o, "static SageValue sage_struct_get(SageValue d, SageValue k, SageValue defv) {" + NL)
    push(o, "    if (d.type != SAGE_TAG_DICT || k.type != SAGE_TAG_STRING) return defv;" + NL)
    push(o, "    for (int i = 0; i < d.as.dict->count; i++) {" + NL)
    push(o, "        if (strcmp(d.as.dict->keys[i], k.as.string) == 0) return d.as.dict->values[i];" + NL)
    push(o, "    }" + NL)
    push(o, "    return defv;" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_struct_set(SageValue d, SageValue k, SageValue t, SageValue val) {" + NL)
    push(o, "    (void)t;" + NL)
    push(o, "    if (d.type != SAGE_TAG_DICT || k.type != SAGE_TAG_STRING) return val;" + NL)
    push(o, "        for (int i = 0; i < d.as.dict->count; i++) {" + NL)
    push(o, "            if (strcmp(d.as.dict->keys[i], k.as.string) == 0) { d.as.dict->values[i] = val; return val; }" + NL)
    push(o, "        }" + NL)
    push(o, "        if (d.as.dict->count >= d.as.dict->capacity) {" + NL)
    push(o, "            int nc = d.as.dict->capacity ? d.as.dict->capacity * 2 : 8;" + NL)
    push(o, "            d.as.dict->keys = (char**)realloc(d.as.dict->keys, sizeof(char*) * nc);" + NL)
    push(o, "            d.as.dict->values = (SageValue*)realloc(d.as.dict->values, sizeof(SageValue) * nc);" + NL)
    push(o, "            d.as.dict->capacity = nc;" + NL)
    push(o, "        }" + NL)
    push(o, "        d.as.dict->keys[d.as.dict->count] = sage_dup_string(k.as.string);" + NL)
    push(o, "        d.as.dict->values[d.as.dict->count] = val;" + NL)
    push(o, "        d.as.dict->count++;" + NL)
    push(o, "    return val;" + NL)
    push(o, "}" + NL)

    push(o, NL)
    push(o, "static SageValue sage_add(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type == SAGE_TAG_NUMBER && right.type == SAGE_TAG_NUMBER) {" + NL)
    push(o, "        return sage_number(left.as.number + right.as.number);" + NL)
    push(o, "    }" + NL)
    push(o, "    if (left.type == SAGE_TAG_STRING && right.type == SAGE_TAG_STRING) {" + NL)
    push(o, "        size_t len1 = strlen(left.as.string);" + NL)
    push(o, "        size_t len2 = strlen(right.as.string);" + NL)
    push(o, "        char* result = (char*)malloc(len1 + len2 + 1);" + NL)
    push(o, "        if (result == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "        memcpy(result, left.as.string, len1);" + NL)
    push(o, "        memcpy(result + len1, right.as.string, len2 + 1);" + NL)
    push(o, "        return sage_string(result);" + NL)
    push(o, "    }" + NL)
    push(o, "    if (left.type == SAGE_TAG_ARRAY && right.type == SAGE_TAG_ARRAY) {" + NL)
    push(o, "        SageValue out = sage_array();" + NL)
    push(o, "        for (int i = 0; i < left.as.array->count; i++) sage_array_push_raw(out.as.array, left.as.array->elements[i]);" + NL)
    push(o, "        for (int i = 0; i < right.as.array->count; i++) sage_array_push_raw(out.as.array, right.as.array->elements[i]);" + NL)
    push(o, "        return out;" + NL)
    push(o, "    }" + NL)
    push(o, "    sage_fail(" + DQ + "Runtime Error: Operands must be numbers or strings." + DQ + ");" + NL)
    push(o, "    return sage_nil();" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Sub, mul, div, mod
    let num_err = DQ + "Runtime Error: Operands must be numbers." + DQ
    push(o, "static SageValue sage_sub(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    return sage_number(left.as.number - right.as.number);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_mul(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    return sage_number(left.as.number * right.as.number);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_div(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    if (right.as.number == 0) { fprintf(stderr, \"Runtime Error: Division by zero.\\n\"); sage_raise(sage_string(sage_dup_string(\"Division by zero\"))); return sage_nil(); }" + NL)
    push(o, "    return sage_number(left.as.number / right.as.number);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_mod(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    if (right.as.number == 0) { fprintf(stderr, \"Runtime Error: Modulo by zero.\\n\"); sage_raise(sage_string(sage_dup_string(\"Modulo by zero\"))); return sage_nil(); }" + NL)
    push(o, "    return sage_number(fmod(left.as.number, right.as.number));" + NL)
    push(o, "}" + NL)
    # Comparison
    push(o, "static SageValue sage_eq(SageValue left, SageValue right) { return sage_bool(sage_values_equal(left, right)); }" + NL)
    push(o, "static SageValue sage_neq(SageValue left, SageValue right) { return sage_bool(!sage_values_equal(left, right)); }" + NL)
    push(o, "static SageValue sage_gt(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    return sage_bool(left.as.number > right.as.number);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_lt(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    return sage_bool(left.as.number < right.as.number);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_gte(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    return sage_bool(left.as.number >= right.as.number);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_lte(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    return sage_bool(left.as.number <= right.as.number);" + NL)
    push(o, "}" + NL)
    # Logic and bitwise
    push(o, "static SageValue sage_not(SageValue value) { return sage_bool(!sage_truthy(value)); }" + NL)
    push(o, "static SageValue sage_and(SageValue left, SageValue right) { return sage_bool(sage_truthy(left) && sage_truthy(right)); }" + NL)
    push(o, "static SageValue sage_or(SageValue left, SageValue right) { return sage_bool(sage_truthy(left) || sage_truthy(right)); }" + NL)
    push(o, "static SageValue sage_bit_not(SageValue value) {" + NL)
    push(o, "    if (value.type != SAGE_TAG_NUMBER) sage_fail(" + DQ + "Runtime Error: Bitwise NOT operand must be a number." + DQ + ");" + NL)
    push(o, "    return sage_number((double)(~(long long)value.as.number));" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_bit_and(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    return sage_number((double)(((long long)left.as.number) & ((long long)right.as.number)));" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_bit_or(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    return sage_number((double)(((long long)left.as.number) | ((long long)right.as.number)));" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_bit_xor(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    return sage_number((double)(((long long)left.as.number) ^ ((long long)right.as.number)));" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_lshift(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    return sage_number((double)(((long long)left.as.number) << ((long long)right.as.number)));" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_rshift(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    return sage_number((double)(((long long)left.as.number) >> ((long long)right.as.number)));" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # tonumber
    push(o, "static SageValue sage_tonumber(SageValue value) {" + NL)
    push(o, "    if (value.type == SAGE_TAG_NUMBER) return value;" + NL)
    push(o, "    if (value.type == SAGE_TAG_STRING) {" + NL)
    push(o, "        char* end;" + NL)
    push(o, "        double result = strtod(value.as.string, &end);" + NL)
    push(o, "        if (end != value.as.string && *end == '" + bs0 + "') return sage_number(result);" + NL)
    push(o, "    }" + NL)
    push(o, "    return sage_nil();" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Dict builtins
    push(o, "static SageValue sage_dict_keys_fn(SageValue dict_val) {" + NL)
    push(o, "    if (dict_val.type != SAGE_TAG_DICT) return sage_array();" + NL)
    push(o, "    SageValue result = sage_array();" + NL)
    push(o, "    for (int i = 0; i < dict_val.as.dict->count; i++) {" + NL)
    push(o, "        sage_array_push_raw(result.as.array, sage_string(dict_val.as.dict->keys[i]));" + NL)
    push(o, "    }" + NL)
    push(o, "    return result;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_dict_values_fn(SageValue dict_val) {" + NL)
    push(o, "    if (dict_val.type != SAGE_TAG_DICT) return sage_array();" + NL)
    push(o, "    SageValue result = sage_array();" + NL)
    push(o, "    for (int i = 0; i < dict_val.as.dict->count; i++) {" + NL)
    push(o, "        sage_array_push_raw(result.as.array, dict_val.as.dict->values[i]);" + NL)
    push(o, "    }" + NL)
    push(o, "    return result;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_dict_has_fn(SageValue dict_val, SageValue key) {" + NL)
    push(o, "    if (dict_val.type != SAGE_TAG_DICT || key.type != SAGE_TAG_STRING) return sage_bool(0);" + NL)
    push(o, "    for (int i = 0; i < dict_val.as.dict->count; i++) {" + NL)
    push(o, "        if (strcmp(dict_val.as.dict->keys[i], key.as.string) == 0) return sage_bool(1);" + NL)
    push(o, "    }" + NL)
    push(o, "    return sage_bool(0);" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_dict_delete_fn(SageValue dict_val, SageValue key) {" + NL)
    push(o, "    if (dict_val.type != SAGE_TAG_DICT || key.type != SAGE_TAG_STRING) return sage_nil();" + NL)
    push(o, "    SageDict* dict = dict_val.as.dict;" + NL)
    push(o, "    for (int i = 0; i < dict->count; i++) {" + NL)
    push(o, "        if (strcmp(dict->keys[i], key.as.string) == 0) {" + NL)
    push(o, "            free(dict->keys[i]);" + NL)
    push(o, "            for (int j = i; j < dict->count - 1; j++) {" + NL)
    push(o, "                dict->keys[j] = dict->keys[j + 1];" + NL)
    push(o, "                dict->values[j] = dict->values[j + 1];" + NL)
    push(o, "            }" + NL)
    push(o, "            dict->count--;" + NL)
    push(o, "            return sage_bool(1);" + NL)
    push(o, "        }" + NL)
    push(o, "    }" + NL)
    push(o, "    return sage_bool(0);" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # String builtins (upper, lower, strip, split, join, replace)
    push(o, "static SageValue sage_upper(SageValue value) {" + NL)
    push(o, "    if (value.type != SAGE_TAG_STRING) return sage_nil();" + NL)
    push(o, "    size_t len = strlen(value.as.string);" + NL)
    push(o, "    char* result = (char*)malloc(len + 1);" + NL)
    push(o, "    if (result == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    for (size_t i = 0; i < len; i++) result[i] = (char)toupper((unsigned char)value.as.string[i]);" + NL)
    push(o, "    result[len] = '" + bs0 + "';" + NL)
    push(o, "    return sage_string(result);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_lower(SageValue value) {" + NL)
    push(o, "    if (value.type != SAGE_TAG_STRING) return sage_nil();" + NL)
    push(o, "    size_t len = strlen(value.as.string);" + NL)
    push(o, "    char* result = (char*)malloc(len + 1);" + NL)
    push(o, "    if (result == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    for (size_t i = 0; i < len; i++) result[i] = (char)tolower((unsigned char)value.as.string[i]);" + NL)
    push(o, "    result[len] = '" + bs0 + "';" + NL)
    push(o, "    return sage_string(result);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_strip_fn(SageValue value) {" + NL)
    push(o, "    if (value.type != SAGE_TAG_STRING) return sage_nil();" + NL)
    push(o, "    const char* s = value.as.string;" + NL)
    push(o, "    while (*s && isspace((unsigned char)*s)) s++;" + NL)
    push(o, "    const char* end = s + strlen(s);" + NL)
    push(o, "    while (end > s && isspace((unsigned char)*(end - 1))) end--;" + NL)
    push(o, "    size_t len = (size_t)(end - s);" + NL)
    push(o, "    char* result = (char*)malloc(len + 1);" + NL)
    push(o, "    if (result == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    memcpy(result, s, len);" + NL)
    push(o, "    result[len] = '" + bs0 + "';" + NL)
    push(o, "    return sage_string(result);" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # split
    push(o, "static SageValue sage_split_fn(SageValue str_val, SageValue delim_val) {" + NL)
    push(o, "    if (str_val.type != SAGE_TAG_STRING || delim_val.type != SAGE_TAG_STRING) return sage_array();" + NL)
    push(o, "    const char* s = str_val.as.string;" + NL)
    push(o, "    const char* delim = delim_val.as.string;" + NL)
    push(o, "    size_t dlen = strlen(delim);" + NL)
    push(o, "    SageValue result = sage_array();" + NL)
    push(o, "    if (dlen == 0) {" + NL)
    push(o, "        for (size_t i = 0; s[i]; i++) {" + NL)
    push(o, "            char buf[2] = {s[i], '" + bs0 + "'};" + NL)
    push(o, "            sage_array_push_raw(result.as.array, sage_string(sage_dup_string(buf)));" + NL)
    push(o, "        }" + NL)
    push(o, "        return result;" + NL)
    push(o, "    }" + NL)
    push(o, "    const char* start = s;" + NL)
    push(o, "    const char* found;" + NL)
    push(o, "    while ((found = strstr(start, delim)) != NULL) {" + NL)
    push(o, "        size_t len = (size_t)(found - start);" + NL)
    push(o, "        char* part = (char*)malloc(len + 1);" + NL)
    push(o, "        if (part == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "        memcpy(part, start, len);" + NL)
    push(o, "        part[len] = '" + bs0 + "';" + NL)
    push(o, "        sage_array_push_raw(result.as.array, sage_string(part));" + NL)
    push(o, "        start = found + dlen;" + NL)
    push(o, "    }" + NL)
    push(o, "    sage_array_push_raw(result.as.array, sage_string(sage_dup_string(start)));" + NL)
    push(o, "    return result;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # join
    push(o, "static SageValue sage_join_fn(SageValue arr_val, SageValue delim_val) {" + NL)
    push(o, "    if (arr_val.type != SAGE_TAG_ARRAY || delim_val.type != SAGE_TAG_STRING) return sage_nil();" + NL)
    push(o, "    SageArray* arr = arr_val.as.array;" + NL)
    push(o, "    const char* delim = delim_val.as.string;" + NL)
    push(o, "    size_t dlen = strlen(delim);" + NL)
    push(o, "    if (arr->count == 0) return sage_string(sage_dup_string(" + DQ + DQ + "));" + NL)
    push(o, "    size_t total = 0;" + NL)
    push(o, "    for (int i = 0; i < arr->count; i++) {" + NL)
    push(o, "        if (arr->elements[i].type == SAGE_TAG_STRING) total += strlen(arr->elements[i].as.string);" + NL)
    push(o, "        if (i > 0) total += dlen;" + NL)
    push(o, "    }" + NL)
    push(o, "    char* result = (char*)malloc(total + 1);" + NL)
    push(o, "    if (result == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    char* p = result;" + NL)
    push(o, "    for (int i = 0; i < arr->count; i++) {" + NL)
    push(o, "        if (i > 0) { memcpy(p, delim, dlen); p += dlen; }" + NL)
    push(o, "        if (arr->elements[i].type == SAGE_TAG_STRING) {" + NL)
    push(o, "            size_t len = strlen(arr->elements[i].as.string);" + NL)
    push(o, "            memcpy(p, arr->elements[i].as.string, len);" + NL)
    push(o, "            p += len;" + NL)
    push(o, "        }" + NL)
    push(o, "    }" + NL)
    push(o, "    *p = '" + bs0 + "';" + NL)
    push(o, "    return sage_string(result);" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # replace
    push(o, "static SageValue sage_replace_fn(SageValue str_val, SageValue old_val, SageValue new_val) {" + NL)
    push(o, "    if (str_val.type != SAGE_TAG_STRING || old_val.type != SAGE_TAG_STRING || new_val.type != SAGE_TAG_STRING)" + NL)
    push(o, "        return sage_nil();" + NL)
    push(o, "    const char* s = str_val.as.string;" + NL)
    push(o, "    const char* old_s = old_val.as.string;" + NL)
    push(o, "    const char* new_s = new_val.as.string;" + NL)
    push(o, "    size_t old_len = strlen(old_s);" + NL)
    push(o, "    size_t new_len = strlen(new_s);" + NL)
    push(o, "    if (old_len == 0) return sage_string(sage_dup_string(s));" + NL)
    push(o, "    size_t count = 0;" + NL)
    push(o, "    const char* tmp = s;" + NL)
    push(o, "    while ((tmp = strstr(tmp, old_s)) != NULL) { count++; tmp += old_len; }" + NL)
    push(o, "    size_t result_len = strlen(s) + count * (new_len - old_len);" + NL)
    push(o, "    char* result = (char*)malloc(result_len + 1);" + NL)
    push(o, "    if (result == NULL) sage_fail(" + DQ + "Runtime Error: out of memory" + DQ + ");" + NL)
    push(o, "    char* p = result;" + NL)
    push(o, "    while (*s) {" + NL)
    push(o, "        if (strncmp(s, old_s, old_len) == 0) {" + NL)
    push(o, "            memcpy(p, new_s, new_len);" + NL)
    push(o, "            p += new_len;" + NL)
    push(o, "            s += old_len;" + NL)
    push(o, "        } else {" + NL)
    push(o, "            *p++ = *s++;" + NL)
    push(o, "        }" + NL)
    push(o, "    }" + NL)
    push(o, "    *p = '" + bs0 + "';" + NL)
    push(o, "    return sage_string(result);" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Clock and input
    push(o, "#include <time.h>" + NL)
    push(o, "static SageValue sage_clock_fn(void) {" + NL)
    push(o, "    return sage_number((double)clock() / CLOCKS_PER_SEC);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_input_fn(SageValue prompt) {" + NL)
    push(o, "    if (prompt.type == SAGE_TAG_STRING) fputs(prompt.as.string, stdout);" + NL)
    push(o, "    char buf[4096];" + NL)
    push(o, "    if (fgets(buf, sizeof(buf), stdin) == NULL) return sage_nil();" + NL)
    push(o, "    size_t len = strlen(buf);" + NL)
    push(o, "    if (len > 0 && buf[len-1] == '" + bsn + "') buf[--len] = '" + bs0 + "';" + NL)
    push(o, "    return sage_string(sage_dup_string(buf));" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Architecture detection
    push(o, "static SageValue sage_arch_fn(void) {" + NL)
    push(o, "#if defined(__x86_64__) || defined(_M_X64)" + NL)
    push(o, "    return sage_string(" + DQ + "x86_64" + DQ + ");" + NL)
    push(o, "#elif defined(__aarch64__) || defined(_M_ARM64)" + NL)
    push(o, "    return sage_string(" + DQ + "aarch64" + DQ + ");" + NL)
    push(o, "#elif defined(__riscv) && __riscv_xlen == 64" + NL)
    push(o, "    return sage_string(" + DQ + "rv64" + DQ + ");" + NL)
    push(o, "#else" + NL)
    push(o, "    return sage_string(" + DQ + "unknown" + DQ + ");" + NL)
    push(o, "#endif" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # Class/object system
    push(o, "typedef SageValue (*SageMethodFn)(SageValue, int, SageValue*);" + NL)
    push(o, "typedef struct { const char* class_name; const char* method_name; SageMethodFn fn; } SageMethodEntry;" + NL)
    push(o, "typedef struct { const char* name; const char* parent; } SageClassEntry;" + NL)
    push(o, "#define SAGE_MAX_METHODS 256" + NL)
    push(o, "#define SAGE_MAX_CLASSES 64" + NL)
    push(o, "static SageMethodEntry sage_method_table[SAGE_MAX_METHODS];" + NL)
    push(o, "static int sage_method_count = 0;" + NL)
    push(o, "static SageClassEntry sage_class_registry[SAGE_MAX_CLASSES];" + NL)
    push(o, "static int sage_class_count = 0;" + NL)
    push(o, NL)
    push(o, "static void sage_register_class(const char* name, const char* parent) {" + NL)
    push(o, "    if (sage_class_count >= SAGE_MAX_CLASSES) sage_fail(" + DQ + "too many classes" + DQ + ");" + NL)
    push(o, "    sage_class_registry[sage_class_count].name = name;" + NL)
    push(o, "    sage_class_registry[sage_class_count].parent = parent;" + NL)
    push(o, "    sage_class_count++;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static void sage_register_method(const char* cls, const char* name, SageMethodFn fn) {" + NL)
    push(o, "    if (sage_method_count >= SAGE_MAX_METHODS) sage_fail(" + DQ + "too many methods" + DQ + ");" + NL)
    push(o, "    sage_method_table[sage_method_count].class_name = cls;" + NL)
    push(o, "    sage_method_table[sage_method_count].method_name = name;" + NL)
    push(o, "    sage_method_table[sage_method_count].fn = fn;" + NL)
    push(o, "    sage_method_count++;" + NL)
    push(o, "}" + NL)
    push(o, NL)
    # call_method and construct
    push(o, "static SageValue sage_call_method(SageValue obj, const char* method, int argc, SageValue* argv) {" + NL)
    push(o, "    if (obj.type != SAGE_TAG_DICT) {" + NL)
    push(o, "        fprintf(stderr, " + DQ + "Runtime Error: method call on non-instance." + bsn + DQ + ");" + NL)
    push(o, "        exit(1);" + NL)
    push(o, "    }" + NL)
    push(o, "    SageValue class_val = sage_dict_get(obj.as.dict, " + DQ + "__class__" + DQ + ");" + NL)
    push(o, "    if (class_val.type != SAGE_TAG_STRING) {" + NL)
    push(o, "        /* Not a class instance: fall back to callable-field dispatch */" + NL)
    push(o, "        SageValue fval = sage_dict_get(obj.as.dict, method);" + NL)
    push(o, "        if (fval.type == SAGE_TAG_FUNCTION) return sage_call_function_value(fval, argc, argv);" + NL)
    push(o, "        fprintf(stderr, " + DQ + "Runtime Error: no __class__ on instance." + bsn + DQ + ");" + NL)
    push(o, "        exit(1);" + NL)
    push(o, "    }" + NL)
    push(o, "    const char* current = class_val.as.string;" + NL)
    push(o, "    while (current != NULL) {" + NL)
    push(o, "        for (int i = 0; i < sage_method_count; i++) {" + NL)
    push(o, "            if (strcmp(sage_method_table[i].class_name, current) == 0 &&" + NL)
    push(o, "                strcmp(sage_method_table[i].method_name, method) == 0) {" + NL)
    push(o, "                return sage_method_table[i].fn(obj, argc, argv);" + NL)
    push(o, "            }" + NL)
    push(o, "        }" + NL)
    push(o, "        const char* parent = NULL;" + NL)
    push(o, "        for (int j = 0; j < sage_class_count; j++) {" + NL)
    push(o, "            if (strcmp(sage_class_registry[j].name, current) == 0) {" + NL)
    push(o, "                parent = sage_class_registry[j].parent;" + NL)
    push(o, "                break;" + NL)
    push(o, "            }" + NL)
    push(o, "        }" + NL)
    push(o, "        current = parent;" + NL)
    push(o, "    }" + NL)
    push(o, "    fprintf(stderr, " + DQ + "Runtime Error: Undefined method '%s'." + bsn + DQ + ", method);" + NL)
    push(o, "    exit(1);" + NL)
    push(o, "    return sage_nil();" + NL)
    push(o, "}" + NL)
    push(o, NL)
    push(o, "static SageValue sage_construct(const char* class_name, const char* parent_name, int argc, SageValue* argv) {" + NL)
    push(o, "    SageValue inst = sage_make_dict();" + NL)
    push(o, "    sage_dict_set(inst.as.dict, " + DQ + "__class__" + DQ + ", sage_string(class_name));" + NL)
    push(o, "    if (parent_name != NULL) sage_dict_set(inst.as.dict, " + DQ + "__parent__" + DQ + ", sage_string(parent_name));" + NL)
    push(o, "    const char* current = class_name;" + NL)
    push(o, "    while (current != NULL) {" + NL)
    push(o, "        for (int i = 0; i < sage_method_count; i++) {" + NL)
    push(o, "            if (strcmp(sage_method_table[i].class_name, current) == 0 &&" + NL)
    push(o, "                strcmp(sage_method_table[i].method_name, " + DQ + "init" + DQ + ") == 0) {" + NL)
    push(o, "                sage_method_table[i].fn(inst, argc, argv);" + NL)
    push(o, "                return inst;" + NL)
    push(o, "            }" + NL)
    push(o, "        }" + NL)
    push(o, "        const char* parent = NULL;" + NL)
    push(o, "        for (int j = 0; j < sage_class_count; j++) {" + NL)
    push(o, "            if (strcmp(sage_class_registry[j].name, current) == 0) {" + NL)
    push(o, "                parent = sage_class_registry[j].parent;" + NL)
    push(o, "                break;" + NL)
    push(o, "            }" + NL)
    push(o, "        }" + NL)
    push(o, "        current = parent;" + NL)
    push(o, "    }" + NL)
    push(o, "    return inst;" + NL)
    push(o, "}" + NL)
    push(o, NL)

# ============================================================================
# Function & Method Definitions
# ============================================================================

proc emit_proc_prototypes(cc):
    for i in range(len(cc.procs)):
        let proc_entry = cc.procs[i]
        let parts = []
        push(parts, "static SageValue " + proc_entry["c_name"] + "(")
        if proc_entry["needs_cenv"] == true:
            push(parts, "void* _cenv")
        for j in range(proc_entry["param_count"]):
            if j > 0 or proc_entry["needs_cenv"] == true:
                push(parts, ", ")
            push(parts, "SageValue arg" + str(j))
        push(parts, ");" + NL)
        cc_emit(cc, join(parts, ""))
    # First-class function objects: one per named proc.
    for i in range(len(cc.procs)):
        let proc_entry = cc.procs[i]
        cc_emit(cc, "static SageFunction sage_fnobj_" + proc_entry["c_name"] + " = { " + DQ + proc_entry["sage_name"] + DQ + ", " + str(proc_entry["param_count"]) + ", (void*)" + proc_entry["c_name"] + ", NULL };" + NL)
    # Anonymous functions: prototype + object (definition emitted later).
    let anon_proto_src = cc.anon_fns
    if cc.prebind_active and cc.prebound_anons != nil:
        anon_proto_src = cc.prebound_anons
    for i in range(len(anon_proto_src)):
        let af = anon_proto_src[i]
        let parts9 = []
        push(parts9, "static SageValue " + af["c_name"] + "(")
        if af["needs_cenv"] == true:
            push(parts9, "void* _cenv")
        for j in range(af["param_count"]):
            if j > 0 or af["needs_cenv"] == true:
                push(parts9, ", ")
            push(parts9, "SageValue arg" + str(j))
        push(parts9, ");" + NL)
        cc_emit(cc, join(parts9, ""))
        cc_emit(cc, "static SageFunction " + af["fnobj"] + " = { " + DQ + af["label"] + DQ + ", " + str(af["param_count"]) + ", (void*)" + af["c_name"] + ", NULL };" + NL)

proc emit_method_prototypes(cc):
    for i in range(len(cc.classes)):
        let cls = cc.classes[i]
        let method = cls["methods"]
        while method != nil:
            if method.type == 106:
                # STMT_PROC
                let mname = method.name.text
                cc_emit(cc, "static SageValue sage_method_" + cls["class_name"] + "_" + mname + "(SageValue _self, int _argc, SageValue* _argv);" + NL)
            method = method.next

proc emit_global_slots(cc):
    for i in range(len(cc.globals)):
        cc_line(cc, "static SageSlot " + cc.globals[i]["c_name"] + ";")

proc emit_slot_declarations(cc, locals_list):
    for i in range(len(locals_list)):
        cc_line(cc, "SageSlot " + locals_list[i]["c_name"] + " = sage_slot_undefined();")

proc emit_function_definition(cc, stmt):
    let proc_name = stmt.name.text
    let proc_entry = find_proc_entry(cc.procs, proc_name)
    if proc_entry == nil:
        cc.failed = true
        return
    # ---- Generator functions: eager-collect emission --------------------
    if proc_entry["is_generator"] == true:
        let col_name = make_unique_name(cc, "sage_gencollect", proc_name)
        # Collector prototype (void, array out-param first)
        let cp2 = []
        push(cp2, "static void " + col_name + "(SageArray* out")
        for i in range(stmt.param_count):
            push(cp2, ", SageValue arg" + str(i))
        push(cp2, ");" + NL)
        cc_emit(cc, join(cp2, ""))
        # Wrapper: runs collector, wraps array as a generator value.
        let wp = []
        push(wp, "static SageValue " + proc_entry["c_name"] + "(")
        for i in range(stmt.param_count):
            if i > 0:
                push(wp, ", ")
            push(wp, "SageValue arg" + str(i))
        push(wp, ") {" + NL)
        cc_emit(cc, join(wp, ""))
        cc.indent = cc.indent + 1
        cc_line(cc, "SageArray* out = sage_array().as.array;")
        let fwd = []
        push(fwd, "    " + col_name + "(out")
        for i in range(stmt.param_count):
            push(fwd, ", arg" + str(i))
        push(fwd, ");")
        cc_emit(cc, join(fwd, ""))
        cc_line(cc, "return sage_make_generator_from_array(out);")
        cc.indent = cc.indent - 1
        cc_line(cc, "}")
        cc_blank(cc)
        # Collector definition with YIELD -> push translation.
        let params_g = []
        for i in range(stmt.param_count):
            add_name_entry(cc, params_g, stmt.params[i].text, "sage_param")
        let prev_locals_g = cc.locals
        let prev_defers_g = cc.defer_scopes
        let prev_gen_out = cc.gen_out_var
        push(cc.defer_scopes, [])
        cc.locals = params_g
        cc.gen_collector = true
        cc.gen_out_var = "out"
        collect_local_lets(cc, stmt.body, cc.locals)
        let cg = []
        push(cg, "static void " + col_name + "(SageArray* out")
        for i in range(stmt.param_count):
            push(cg, ", SageValue arg" + str(i))
        push(cg, ") {" + NL)
        cc_emit(cc, join(cg, ""))
        cc.indent = cc.indent + 1
        emit_slot_declarations(cc, cc.locals)
        for i in range(stmt.param_count):
            let pn2 = stmt.params[i].text
            let pe3 = find_name_entry(cc.locals, pn2)
            cc_line(cc, "sage_define_slot(&" + pe3["c_name"] + ", arg" + str(i) + ");")
        cc_emit_stmt_list(cc, stmt.body)
        let gscope = cc.defer_scopes[len(cc.defer_scopes) - 1]
        let gi = len(gscope) - 1
        while gi >= 0:
            cc_emit_stmt(cc, gscope[gi])
            gi = gi - 1
        pop(cc.defer_scopes)
        cc.gen_out_var = prev_gen_out
        cc.gen_collector = false
        cc.indent = cc.indent - 1
        cc_line(cc, "}")
        cc_blank(cc)
        cc.defer_scopes = prev_defers_g
        cc.locals = prev_locals_g
        return
    # Set up params as locals
    let params = []
    for i in range(stmt.param_count):
        let pname = stmt.params[i].text
        add_name_entry(cc, params, pname, "sage_param")
    let prev_locals = cc.locals
    let prev_defers = cc.defer_scopes
    push(cc.defer_scopes, [])
    cc.locals = params
    collect_local_lets(cc, stmt.body, cc.locals)

    # ---- Closure capture: promote locals into a heap environment -------
    let promoting = stmt_body_has_nested_fn(stmt.body)
    let env_type = ""
    let env_var = ""
    let frame = {"promoting": false, "env_var": "", "fields": {}}
    if promoting:
        env_type = make_unique_name(cc, "SageEnv", proc_name)
        env_var = make_unique_name(cc, "sage_env", proc_name)
        let fields = {}
        let td = []
        push(td, "typedef struct {" + NL)
        for i in range(len(cc.locals)):
            let e9 = cc.locals[i]
            fields[e9["sage_name"]] = e9["c_name"]
            push(td, "    SageSlot " + e9["c_name"] + ";" + NL)
        push(td, "} " + env_type + ";" + NL)
        frame["promoting"] = true
        frame["env_var"] = env_var
        frame["env_type"] = env_type
        frame["deref"] = env_var
        frame["fields"] = fields
        # Typedef precedes this definition; hoisted children are emitted
        # later in the file, so the type is always declared before use.
        cc_emit(cc, join(td, ""))

    # Emit function signature. Only hoisted children of capturing parents
    # receive the hidden environment parameter.
    let parts = []
    push(parts, "static SageValue " + proc_entry["c_name"] + "(")
    let sig_cenv = proc_entry["needs_cenv"] == true
    if sig_cenv:
        push(parts, "void* _cenv")
    for i in range(stmt.param_count):
        if i > 0 or sig_cenv:
            push(parts, ", ")
        push(parts, "SageValue arg" + str(i))
    push(parts, ") {" + NL)
    cc_emit(cc, join(parts, ""))
    cc.indent = cc.indent + 1
    if promoting:
        cc_line(cc, env_type + "* " + env_var + " = (" + env_type + "*)malloc(sizeof(" + env_type + "));")
        for i in range(len(cc.locals)):
            let e10 = cc.locals[i]
            cc_line(cc, "sage_define_slot(&" + env_var + "->" + e10["c_name"] + ", sage_nil());")
    # Declare local slots, excluding promoted (environment-resident) names.
    if promoting:
        let non_promoted = []
        for i in range(len(cc.locals)):
            let e11 = cc.locals[i]
            if not dict_has(frame["fields"], e11["sage_name"]):
                push(non_promoted, e11)
        emit_slot_declarations(cc, non_promoted)
    else:
        emit_slot_declarations(cc, cc.locals)
    # Bind params
    for i in range(stmt.param_count):
        let pname = stmt.params[i].text
        let param_entry = find_name_entry(cc.locals, pname)
        if promoting:
            cc_line(cc, "sage_define_slot(&" + env_var + "->" + param_entry["c_name"] + ", arg" + str(i) + ");")
        else:
            cc_line(cc, "sage_define_slot(&" + param_entry["c_name"] + ", arg" + str(i) + ");")
    # Capture context for nested definitions discovered in this body
    push(cc.fn_stack, frame)
    # Emit body
    cc_emit_stmt_list(cc, stmt.body)
    let end_scope = cc.defer_scopes[len(cc.defer_scopes) - 1]
    let ei = len(end_scope) - 1
    while ei >= 0:
        cc_emit_stmt(cc, end_scope[ei])
        ei = ei - 1
    cc_line(cc, "return sage_nil();")
    cc.indent = cc.indent - 1
    cc_line(cc, "}")
    pop(cc.fn_stack)
    cc_blank(cc)
    cc.defer_scopes = prev_defers
    cc.locals = prev_locals

proc emit_method_definition(cc, cls, method):
    let mname = method.name.text
    let has_self = false
    if method.param_count > 0:
        if method.params[0].text == "self":
            has_self = true
    let param_start = 0
    if has_self:
        param_start = 1
    let prev_locals = cc.locals
    let prev_defers_m = cc.defer_scopes
    push(cc.defer_scopes, [])
    cc.locals = []
    add_name_entry(cc, cc.locals, "self", "sage_local")
    for i in range(param_start, method.param_count):
        let pname = method.params[i].text
        if find_name_entry(cc.locals, pname) == nil:
            add_name_entry(cc, cc.locals, pname, "sage_local")
    collect_local_lets(cc, method.body, cc.locals)
    cc_emit(cc, "static SageValue sage_method_" + cls["class_name"] + "_" + mname + "(SageValue _self, int _argc, SageValue* _argv) {" + NL)
    cc.indent = cc.indent + 1
    emit_slot_declarations(cc, cc.locals)
    # Bind self
    let self_entry = find_name_entry(cc.locals, "self")
    cc_line(cc, "sage_define_slot(&" + self_entry["c_name"] + ", _self);")
    # Bind params from argv
    let argv_idx = 0
    for i in range(param_start, method.param_count):
        let pname = method.params[i].text
        let entry = find_name_entry(cc.locals, pname)
        cc_line(cc, "sage_define_slot(&" + entry["c_name"] + ", _argv[" + str(argv_idx) + "]);")
        argv_idx = argv_idx + 1
    cc_line(cc, "(void)_argc;")
    cc_emit_stmt_list(cc, method.body)
    let mscope = cc.defer_scopes[len(cc.defer_scopes) - 1]
    let mi = len(mscope) - 1
    while mi >= 0:
        cc_emit_stmt(cc, mscope[mi])
        mi = mi - 1
    cc_line(cc, "return sage_nil();")
    cc.indent = cc.indent - 1
    cc_line(cc, "}")
    cc_blank(cc)
    cc.locals = prev_locals

proc emit_function_definitions(cc, program):
    # Class methods
    for i in range(len(cc.classes)):
        let cls = cc.classes[i]
        let method = cls["methods"]
        while method != nil:
            if method.type == 106:
                emit_method_definition(cc, cls, method)
                if cc.failed:
                    return
            method = method.next
    # Program functions
    let stmt = program
    while stmt != nil:
        if stmt.type == 106:
            emit_function_definition(cc, stmt)
            if cc.failed:
                return
        stmt = stmt.next

# ============================================================================
# Main Function Emission
proc emit_anon_definition(cc, af):
    if af["emitted"]:
        return
    af["emitted"] = true
    let out_len = len(cc.output)
    let prev_failed = cc.failed
    cc.failed = false
    let needs_cenv = af["needs_cenv"] == true
    let saved_frames = cc.fn_stack
    if needs_cenv and af["frames"] != nil:
        cc.fn_stack = []
        for fi13 in range(len(af["frames"])):
            let fr13 = af["frames"][fi13]
            fr13["deref"] = "((" + fr13["env_type"] + "*)" + "_cenv)"
            push(cc.fn_stack, fr13)
    if not af["prototyped"]:
        let parts = []
        push(parts, "static SageValue " + af["c_name"] + "(")
        if needs_cenv:
            push(parts, "void* _cenv")
        for i in range(af["param_count"]):
            if i > 0 or needs_cenv:
                push(parts, ", ")
            push(parts, "SageValue arg" + str(i))
            if i > 0:
                push(parts, ", ")
            push(parts, "SageValue arg" + str(i))
        push(parts, ");" + NL)
        cc_emit(cc, join(parts, ""))
        cc_emit(cc, "static SageFunction " + af["fnobj"] + " = { " + DQ + af["label"] + DQ + ", " + str(af["param_count"]) + ", (void*)" + af["c_name"] + ", NULL };" + NL)
    let prev_locals = cc.locals
    let prev_defers = cc.defer_scopes
    push(cc.defer_scopes, [])
    cc.locals = []
    # Register parameters before walking the body so references resolve.
    for i in range(af["param_count"]):
        add_name_entry(cc, cc.locals, af["params"][i].text, "sage_param")
    collect_local_lets(cc, af["body"], cc.locals)
    let sig = []
    push(sig, "static SageValue " + af["c_name"] + "(")
    if needs_cenv:
        push(sig, "void* _cenv")
    for i in range(af["param_count"]):
        if i > 0 or needs_cenv:
            push(sig, ", ")
        push(sig, "SageValue arg" + str(i))
    push(sig, ") {")
    cc_emit(cc, join(sig, ""))
    cc.indent = cc.indent + 1
    emit_slot_declarations(cc, cc.locals)
    for i in range(af["param_count"]):
        let pname = af["params"][i].text
        let pe2 = find_name_entry(cc.locals, pname)
        if pe2 != nil:
            cc_line(cc, "sage_define_slot(&" + pe2["c_name"] + ", arg" + str(i) + ");")
    if af["body"] != nil and af["body"].type == 104:
        cc_emit_stmt_list(cc, af["body"].statements)
    else:
        cc_emit_stmt_list(cc, af["body"])
    let scope = cc.defer_scopes[len(cc.defer_scopes) - 1]
    let si4 = len(scope) - 1
    while si4 >= 0:
        cc_emit_stmt(cc, scope[si4])
        si4 = si4 - 1
    pop(cc.defer_scopes)
    cc_line(cc, "return sage_nil();")
    cc.indent = cc.indent - 1
    cc_line(cc, "}")
    cc_blank(cc)
    if cc.failed:
        cc.output = slice(cc.output, 0, out_len)
        if not af["prototyped"]:
            cc_emit(cc, "static SageFunction " + af["fnobj"] + " = { " + DQ + af["label"] + DQ + ", " + str(af["param_count"]) + ", (void*)" + af["c_name"] + ", NULL };" + NL)
        cc.failed = prev_failed
        cc.fn_stack = saved_frames
    else:
        cc.failed = prev_failed
        cc.fn_stack = saved_frames
    cc.defer_scopes = prev_defers
    cc.locals = prev_locals

proc emit_anon_flush(cc):
    let i5 = 0
    while i5 < len(cc.anon_fns):
        emit_anon_definition(cc, cc.anon_fns[i5])
        i5 = i5 + 1
    let h6 = 0
    while h6 < len(cc.hoisted_defs):
        emit_hoisted_definition(cc, cc.hoisted_defs[h6])
        h6 = h6 + 1

# Hoisted nested named proc: void*-env taking definition.
proc emit_hoisted_definition(cc, hd):
    let stmt2 = hd["stmt"]
    let entry2 = hd["entry"]
    let f0 = hd["frames"][len(hd["frames"]) - 1]
    # Restore capture frames captured at queue time.
    let saved_frames = cc.fn_stack
    cc.fn_stack = []
    for fi14 in range(len(hd["frames"])):
        let fr14 = hd["frames"][fi14]
        fr14["deref"] = "((" + fr14["env_type"] + "*)" + "_cenv)"
        push(cc.fn_stack, fr14)
    let prev_locals = cc.locals
    let prev_defers = cc.defer_scopes
    push(cc.defer_scopes, [])
    cc.locals = []
    collect_local_lets(cc, stmt2.body, cc.locals)
    let sig = []
    push(sig, "static SageValue " + entry2["c_name"] + "(void* _cenv")
    for i in range(stmt2.param_count):
        push(sig, ", SageValue arg" + str(i))
    push(sig, ") {")
    cc_emit(cc, join(sig, ""))
    cc.indent = cc.indent + 1
    emit_slot_declarations(cc, cc.locals)
    for i in range(stmt2.param_count):
        let pname = stmt2.params[i].text
        let pe6 = find_name_entry(cc.locals, pname)
        if pe6 != nil:
            cc_line(cc, "sage_define_slot(&" + pe6["c_name"] + ", arg" + str(i) + ");")
    cc_emit_stmt_list(cc, stmt2.body)
    let scope6 = cc.defer_scopes[len(cc.defer_scopes) - 1]
    let si7 = len(scope6) - 1
    while si7 >= 0:
        cc_emit_stmt(cc, scope6[si7])
        si7 = si7 - 1
    pop(cc.defer_scopes)
    cc_line(cc, "return sage_nil();")
    cc.indent = cc.indent - 1
    cc_line(cc, "}")
    cc_blank(cc)
    cc.locals = prev_locals
    cc.defer_scopes = prev_defers
    cc.fn_stack = saved_frames

# ============================================================================
# Main Function Emission
# ============================================================================

proc emit_main_function(cc, program):
    cc_line(cc, "static int g_sage_argc = 0;")
    cc_line(cc, "static char** g_sage_argv = NULL;")
    cc_line(cc, "static SageValue sage_args_v(void) { SageValue o = sage_array(); for (int i = 0; i < g_sage_argc; i++) sage_array_push_raw(o.as.array, sage_string(g_sage_argv[i])); return o; }")
    cc_line(cc, "int main(int argc, char** argv) { g_sage_argc = argc; g_sage_argv = argv;")
    cc.indent = cc.indent + 1
    # Init global slots
    for i in range(len(cc.globals)):
        cc_line(cc, cc.globals[i]["c_name"] + " = sage_slot_undefined();")
    # Register classes and methods
    for i in range(len(cc.classes)):
        let cls = cc.classes[i]
        if cls["parent_name"] != nil:
            cc_line(cc, "sage_register_class(" + DQ + cls["class_name"] + DQ + ", " + DQ + cls["parent_name"] + DQ + ");")
        if cls["parent_name"] == nil:
            cc_line(cc, "sage_register_class(" + DQ + cls["class_name"] + DQ + ", NULL);")
        let method = cls["methods"]
        while method != nil:
            if method.type == 106:
                let mn = method.name.text
                cc_line(cc, "sage_register_method(" + DQ + cls["class_name"] + DQ + ", " + DQ + mn + DQ + ", sage_method_" + cls["class_name"] + "_" + mn + ");")
            method = method.next
    # Emit top-level statements
    let stmt = program
    while stmt != nil:
        if stmt.type != 106 and stmt.type != 111:
            cc_emit_stmt(cc, stmt)
            if cc.failed:
                cc.indent = cc.indent - 1
                cc_line(cc, "return 1;")
                cc_line(cc, "}")
                return
        stmt = stmt.next
    cc_line(cc, "return 0;")
    cc.indent = cc.indent - 1
    cc_line(cc, "}")

# ============================================================================
# Public API
# ============================================================================

proc compile_to_c(program):
    let was_array = (type(program) == "array")
    if was_array:
        if len(program) == 0:
            program = nil
        else:
            for i in range(len(program) - 1):
                program[i].next = program[i + 1]
            program[len(program) - 1].next = nil
            program = program[0]
    # Pass 1 — discovery: identical pipeline into a throwaway compiler so
    # every anonymous function is registered with a stable name/order.
    let probe = CCompiler()
    probe.prebind_active = false
    collect_top_level_symbols(probe, program)
    emit_runtime_prelude(probe)
    probe.indent = 0
    emit_proc_prototypes(probe)
    emit_method_prototypes(probe)
    emit_global_slots(probe)
    emit_function_definitions(probe, program)
    emit_main_function(probe, program)
    let discovered = probe.anon_fns

    # Pass 2 — real emission with anon entries pre-bound.
    let cc = CCompiler()
    let prebound = []
    for i in range(len(discovered)):
        let src_e = discovered[i]
        let e2 = {}
        e2["c_name"] = src_e["c_name"]
        e2["fnobj"] = src_e["fnobj"]
        e2["label"] = src_e["label"]
        e2["param_count"] = src_e["param_count"]
        e2["params"] = src_e["params"]
        e2["body"] = src_e["body"]
        e2["emitted"] = false
        e2["prototyped"] = true
        e2["needs_cenv"] = src_e["needs_cenv"]
        e2["frames"] = src_e["frames"]
        push(prebound, e2)
    cc.prebound_anons = prebound
    cc.anon_fns = []
    cc.prebind_active = true
    # Pre-register nested named procs discovered during the probe pass so
    # their environment-taking prototypes are emitted up-front.
    for i8 in range(len(probe.discovered_nested)):
        let dn = probe.discovered_nested[i8]
        let dn_entry = add_proc_entry(cc, dn["name"], dn["param_count"], dn["param_defaults"])
        dn_entry["needs_cenv"] = true
    collect_top_level_symbols(cc, program)
    if cc.failed:
        return ""
    emit_runtime_prelude(cc)
    cc.indent = 0
    emit_proc_prototypes(cc)
    emit_method_prototypes(cc)
    if len(cc.procs) > 0 or len(cc.classes) > 0:
        cc_blank(cc)
    emit_global_slots(cc)
    if len(cc.globals) > 0:
        cc_blank(cc)
    emit_function_definitions(cc, program)
    if cc.failed:
        return ""
    emit_main_function(cc, program)
    # Anonymous functions discovered while emitting main (or nested ones)
    # get their definitions here; prototypes were emitted up front.
    emit_anon_flush(cc)
    return join(cc.output, "")