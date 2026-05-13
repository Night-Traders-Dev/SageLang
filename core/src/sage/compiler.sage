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

proc add_proc_entry(cc, sage_name, param_count):
    let existing = find_proc_entry(cc.procs, sage_name)
    if existing != nil:
        return existing
    let entry = {}
    entry["sage_name"] = sage_name
    entry["c_name"] = make_unique_name(cc, "sage_fn", sage_name)
    entry["param_count"] = param_count
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
            add_proc_entry(cc, stmt.name.text, stmt.param_count)
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

proc resolve_slot_name(cc, sage_name):
    let local = find_name_entry(cc.locals, sage_name)
    if local != nil:
        return local["c_name"]
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
    if op_type == 11:
        return "sage_not(" + left + ")"
    # Unary bitwise NOT
    if op_type == 56:
        return "sage_bit_not(" + left + ")"
    let right = cc_emit_expr(cc, expr.right)
    let helper = nil
    if op_type == 34:
        helper = "sage_add"
    if op_type == 35:
        helper = "sage_sub"
    if op_type == 36:
        helper = "sage_mul"
    if op_type == 37:
        helper = "sage_div"
    if op_type == 38:
        helper = "sage_mod"
    if op_type == 40:
        helper = "sage_eq"
    if op_type == 41:
        helper = "sage_neq"
    if op_type == 43:
        helper = "sage_gt"
    if op_type == 42:
        helper = "sage_lt"
    if op_type == 45:
        helper = "sage_gte"
    if op_type == 44:
        helper = "sage_lte"
    if op_type == 53:
        helper = "sage_bit_and"
    if op_type == 54:
        helper = "sage_bit_or"
    if op_type == 55:
        helper = "sage_bit_xor"
    if op_type == 57:
        helper = "sage_lshift"
    if op_type == 58:
        helper = "sage_rshift"
    if op_type == 9:
        helper = "sage_and"
    if op_type == 10:
        helper = "sage_or"
    if helper == nil:
        cc.failed = true
        return "sage_nil()"
    return helper + "(" + left + ", " + right + ")"

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
        # Not EXPR_VARIABLE
        cc.failed = true
        return "sage_nil()"
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
            return "sage_mem_alloc(" + cc_emit_expr(cc, call_expr.args[0]) + ")"
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
    # User-defined function call
    let proc_entry = find_proc_entry(cc.procs, name)
    if proc_entry == nil:
        cc.failed = true
        return "sage_nil()"
    let parts = []
    push(parts, proc_entry["c_name"])
    push(parts, "(")
    for i in range(argc):
        if i > 0:
            push(parts, ", ")
        push(parts, cc_emit_expr(cc, call_expr.args[i]))
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
            cc.failed = true
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
    if stmt != nil and stmt.type == 104:
        # STMT_BLOCK
        cc_emit_stmt_list(cc, stmt.statements)
    if stmt != nil and stmt.type != 104:
        cc_emit_stmt_list(cc, stmt)
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
    if t == 108:
        # STMT_RETURN
        let ret_val = "sage_nil()"
        if stmt.value != nil:
            ret_val = cc_emit_expr(cc, stmt.value)
        cc_line(cc, "return " + ret_val + ";")
        return
    if t == 109:
        # STMT_BREAK
        cc_line(cc, "break;")
        return
    if t == 110:
        # STMT_CONTINUE
        cc_line(cc, "continue;")
        return
    if t == 106:
        # STMT_PROC - handled at top level
        return
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
        cc_line(cc, "if (" + iter_var + ".type == SAGE_TAG_ARRAY) {")
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
        cc_line(cc, "char _ch[2] = {" + iter_var + ".as.string[" + idx_var + "], " + BS + "0" + "};")
        cc_line(cc, "sage_define_slot(&" + slot + ", sage_string(sage_dup_string(_ch)));")
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
        cc_line(cc, "if (sage_try_depth >= SAGE_MAX_TRY_DEPTH) sage_fail(" + DQ + "Runtime Error: try nesting too deep" + DQ + ");")
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
    push(o, "    SAGE_TAG_TUPLE" + NL)
    push(o, "} SageTag;" + NL)
    push(o, NL)
    push(o, "struct SageValue {" + NL)
    push(o, "    SageTag type;" + NL)
    push(o, "    union {" + NL)
    push(o, "        double number;" + NL)
    push(o, "        int boolean;" + NL)
    push(o, "        const char* string;" + NL)
    push(o, "        SageArray* array;" + NL)
    push(o, "        SageDict* dict;" + NL)
    push(o, "        SageTuple* tuple;" + NL)
    push(o, "    } as;" + NL)
    push(o, "};" + NL)
    push(o, NL)
    push(o, "typedef struct {" + NL)
    push(o, "    int defined;" + NL)
    push(o, "    SageValue value;" + NL)
    push(o, "} SageSlot;" + NL)
    push(o, NL)
    # Exception handling
    push(o, "#define SAGE_MAX_TRY_DEPTH 64" + NL)
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
    push(o, "    dict->keys = NULL;" + NL)
    push(o, "    dict->values = NULL;" + NL)
    push(o, "    dict->count = 0;" + NL)
    push(o, "    dict->capacity = 0;" + NL)
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
    push(o, "static SageValue sage_load_slot(const SageSlot* slot, const char* name) {" + NL)
    push(o, "    if (!slot->defined) {" + NL)
    push(o, "        fprintf(stderr, " + DQ + "Runtime Error: Undefined variable '%s'." + bsn + DQ + ", name);" + NL)
    push(o, "        exit(1);" + NL)
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
    push(o, "        exit(1);" + NL)
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
    push(o, "    if (right.as.number == 0) return sage_nil();" + NL)
    push(o, "    return sage_number(left.as.number / right.as.number);" + NL)
    push(o, "}" + NL)
    push(o, "static SageValue sage_mod(SageValue left, SageValue right) {" + NL)
    push(o, "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(" + num_err + ");" + NL)
    push(o, "    if ((int)right.as.number == 0) return sage_nil();" + NL)
    push(o, "    return sage_number((double)((int)left.as.number % (int)right.as.number));" + NL)
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
    push(o, "#include <ctype.h>" + NL)
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
        for j in range(proc_entry["param_count"]):
            if j > 0:
                push(parts, ", ")
            push(parts, "SageValue arg" + str(j))
        push(parts, ");" + NL)
        cc_emit(cc, join(parts, ""))

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
    # Set up params as locals
    let params = []
    for i in range(stmt.param_count):
        let pname = stmt.params[i].text
        add_name_entry(cc, params, pname, "sage_param")
    let prev_locals = cc.locals
    cc.locals = params
    collect_local_lets(cc, stmt.body, cc.locals)
    # Emit function signature
    let parts = []
    push(parts, "static SageValue " + proc_entry["c_name"] + "(")
    for i in range(stmt.param_count):
        if i > 0:
            push(parts, ", ")
        push(parts, "SageValue arg" + str(i))
    push(parts, ") {" + NL)
    cc_emit(cc, join(parts, ""))
    cc.indent = cc.indent + 1
    # Declare local slots
    emit_slot_declarations(cc, cc.locals)
    # Bind params
    for i in range(stmt.param_count):
        let pname = stmt.params[i].text
        let param_entry = find_name_entry(cc.locals, pname)
        cc_line(cc, "sage_define_slot(&" + param_entry["c_name"] + ", arg" + str(i) + ");")
    # Emit body
    cc_emit_stmt_list(cc, stmt.body)
    cc_line(cc, "return sage_nil();")
    cc.indent = cc.indent - 1
    cc_line(cc, "}")
    cc_blank(cc)
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
# ============================================================================

proc emit_main_function(cc, program):
    cc_line(cc, "int main(void) {")
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
    let cc = CCompiler()
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
    return join(cc.output, "")
