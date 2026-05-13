gc_disable()
# ============================================================================
# codegen.sage - Instruction Selection + Assembly Text Emission
#
# Port of src/c/codegen.c
# Converts Sage AST to VInst IR, then emits assembly text for
# x86-64, aarch64, and rv64 targets.
# ============================================================================
import token
import ast

# ============================================================================
# VInst Kind Constants
# ============================================================================

let VINST_LOAD_IMM = 0
let VINST_LOAD_STRING = 1
let VINST_LOAD_BOOL = 2
let VINST_LOAD_NIL = 3
let VINST_LOAD_GLOBAL = 4
let VINST_STORE_GLOBAL = 5
let VINST_ADD = 6
let VINST_SUB = 7
let VINST_MUL = 8
let VINST_DIV = 9
let VINST_MOD = 10
let VINST_EQ = 11
let VINST_NEQ = 12
let VINST_LT = 13
let VINST_GT = 14
let VINST_LTE = 15
let VINST_GTE = 16
let VINST_AND = 17
let VINST_OR = 18
let VINST_NOT = 19
let VINST_PRINT = 20
let VINST_CALL = 21
let VINST_CALL_BUILTIN = 22
let VINST_RET = 23
let VINST_BRANCH = 24
let VINST_JUMP = 25
let VINST_LABEL = 26
let VINST_INDEX = 27
let VINST_ARRAY_NEW = 28
let VINST_ARRAY_SET = 29

# ============================================================================
# Target Constants
# ============================================================================

let TARGET_X86_64 = 0
let TARGET_AARCH64 = 1
let TARGET_RV64 = 2

proc target_name(t):
    if t == TARGET_X86_64:
        return "x86_64"
    if t == TARGET_AARCH64:
        return "aarch64"
    if t == TARGET_RV64:
        return "rv64"
    return "unknown"

# ============================================================================
# VInst Node
# ============================================================================

proc vinst_kind_name(kind):
    if kind == VINST_LOAD_IMM:
        return "LOAD_IMM"
    if kind == VINST_LOAD_STRING:
        return "LOAD_STRING"
    if kind == VINST_LOAD_BOOL:
        return "LOAD_BOOL"
    if kind == VINST_LOAD_NIL:
        return "LOAD_NIL"
    if kind == VINST_LOAD_GLOBAL:
        return "LOAD_GLOBAL"
    if kind == VINST_STORE_GLOBAL:
        return "STORE_GLOBAL"
    if kind == VINST_ADD:
        return "ADD"
    if kind == VINST_SUB:
        return "SUB"
    if kind == VINST_MUL:
        return "MUL"
    if kind == VINST_DIV:
        return "DIV"
    if kind == VINST_MOD:
        return "MOD"
    if kind == VINST_EQ:
        return "EQ"
    if kind == VINST_NEQ:
        return "NEQ"
    if kind == VINST_LT:
        return "LT"
    if kind == VINST_GT:
        return "GT"
    if kind == VINST_LTE:
        return "LTE"
    if kind == VINST_GTE:
        return "GTE"
    if kind == VINST_AND:
        return "AND"
    if kind == VINST_OR:
        return "OR"
    if kind == VINST_NOT:
        return "NOT"
    if kind == VINST_PRINT:
        return "PRINT"
    if kind == VINST_CALL:
        return "CALL"
    if kind == VINST_CALL_BUILTIN:
        return "CALL_BUILTIN"
    if kind == VINST_RET:
        return "RET"
    if kind == VINST_BRANCH:
        return "BRANCH"
    if kind == VINST_JUMP:
        return "JUMP"
    if kind == VINST_LABEL:
        return "LABEL"
    if kind == VINST_INDEX:
        return "INDEX"
    if kind == VINST_ARRAY_NEW:
        return "ARRAY_NEW"
    if kind == VINST_ARRAY_SET:
        return "ARRAY_SET"
    return "UNKNOWN"

proc vinst_new(kind):
    let v = {}
    v["kind"] = kind
    v["dest"] = -1
    v["src1"] = -1
    v["src2"] = -1
    v["imm_number"] = 0
    v["imm_string"] = nil
    v["imm_bool"] = false
    v["label"] = nil
    v["label_false"] = nil
    v["func_name"] = nil
    v["call_args"] = nil
    v["call_arg_count"] = 0
    v["next"] = nil
    return v

# ============================================================================
# Instruction Selection Context
# ============================================================================

class ISelContext:
    proc init():
        self.next_vreg = 0
        self.next_label = 0
        self.head = nil
        self.tail = nil
        self.string_pool = []
        self.string_pool_count = 0
        self.loop_cond_labels = []
        self.loop_end_labels = []
        self.loop_depth = 0

proc isel_append(ctx, v):
    if ctx.head == nil:
        ctx.head = v
    else:
        ctx.tail["next"] = v
    ctx.tail = v

proc isel_vreg(ctx):
    let r = ctx.next_vreg
    ctx.next_vreg = ctx.next_vreg + 1
    return r

proc isel_label(ctx):
    let lab = ".L" + str(ctx.next_label)
    ctx.next_label = ctx.next_label + 1
    return lab

proc isel_add_string(ctx, s):
    push(ctx.string_pool, s)
    let idx = ctx.string_pool_count
    ctx.string_pool_count = ctx.string_pool_count + 1
    return idx

# ============================================================================
# Instruction Selection - Expression
# ============================================================================

proc isel_expr(ctx, expr):
    if expr == nil:
        let r = isel_vreg(ctx)
        let v = vinst_new(VINST_LOAD_NIL)
        v["dest"] = r
        isel_append(ctx, v)
        return r
    let t = expr.type
    if t == ast.EXPR_NUMBER:
        let r = isel_vreg(ctx)
        let v = vinst_new(VINST_LOAD_IMM)
        v["dest"] = r
        v["imm_number"] = expr.value
        isel_append(ctx, v)
        return r
    if t == ast.EXPR_STRING:
        let r = isel_vreg(ctx)
        let v = vinst_new(VINST_LOAD_STRING)
        v["dest"] = r
        v["imm_string"] = expr.value
        isel_append(ctx, v)
        isel_add_string(ctx, expr.value)
        return r
    if t == ast.EXPR_BOOL:
        let r = isel_vreg(ctx)
        let v = vinst_new(VINST_LOAD_BOOL)
        v["dest"] = r
        v["imm_bool"] = expr.value
        isel_append(ctx, v)
        return r
    if t == ast.EXPR_NIL:
        let r = isel_vreg(ctx)
        let v = vinst_new(VINST_LOAD_NIL)
        v["dest"] = r
        isel_append(ctx, v)
        return r
    if t == ast.EXPR_BINARY:
        let left = isel_expr(ctx, expr.left)
        let right = isel_expr(ctx, expr.right)
        let r = isel_vreg(ctx)
        let op_type = expr.op.type
        let kind = VINST_ADD
        if op_type == token.TOKEN_PLUS:
            kind = VINST_ADD
        if op_type == token.TOKEN_MINUS:
            kind = VINST_SUB
        if op_type == token.TOKEN_STAR:
            kind = VINST_MUL
        if op_type == token.TOKEN_SLASH:
            kind = VINST_DIV
        if op_type == token.TOKEN_PERCENT:
            kind = VINST_MOD
        if op_type == token.TOKEN_LT:
            kind = VINST_LT
        if op_type == token.TOKEN_GT:
            kind = VINST_GT
        if op_type == token.TOKEN_EQ:
            kind = VINST_EQ
        if op_type == token.TOKEN_NEQ:
            kind = VINST_NEQ
        if op_type == token.TOKEN_LTE:
            kind = VINST_LTE
        if op_type == token.TOKEN_GTE:
            kind = VINST_GTE
        if op_type == token.TOKEN_AND:
            kind = VINST_AND
        if op_type == token.TOKEN_OR:
            kind = VINST_OR
        let v = vinst_new(kind)
        v["dest"] = r
        v["src1"] = left
        v["src2"] = right
        isel_append(ctx, v)
        return r
    if t == ast.EXPR_VARIABLE:
        let r = isel_vreg(ctx)
        let name = expr.name.text
        let v = vinst_new(VINST_LOAD_GLOBAL)
        v["dest"] = r
        v["imm_string"] = name
        isel_append(ctx, v)
        return r
    if t == ast.EXPR_CALL:
        let arg_regs = []
        for i in range(expr.arg_count):
            push(arg_regs, isel_expr(ctx, expr.args[i]))
        let r = isel_vreg(ctx)
        if expr.callee.type == ast.EXPR_VARIABLE:
            let name = expr.callee.name.text
            let is_builtin = false
            if name == "str":
                is_builtin = true
            if name == "len":
                is_builtin = true
            if name == "tonumber":
                is_builtin = true
            if name == "push":
                is_builtin = true
            if name == "pop":
                is_builtin = true
            if name == "range":
                is_builtin = true
            let vkind = VINST_CALL
            if is_builtin:
                vkind = VINST_CALL_BUILTIN
            let v = vinst_new(vkind)
            v["dest"] = r
            v["func_name"] = name
            v["call_args"] = arg_regs
            v["call_arg_count"] = expr.arg_count
            isel_append(ctx, v)
            return r
        # Dynamic call not supported
        let v = vinst_new(VINST_LOAD_NIL)
        v["dest"] = r
        isel_append(ctx, v)
        return r
    if t == ast.EXPR_ARRAY:
        let r = isel_vreg(ctx)
        let v = vinst_new(VINST_ARRAY_NEW)
        v["dest"] = r
        v["src1"] = expr.count
        isel_append(ctx, v)
        for i in range(expr.count):
            let elem = isel_expr(ctx, expr.elements[i])
            let set_v = vinst_new(VINST_ARRAY_SET)
            set_v["src1"] = r
            set_v["src2"] = elem
            set_v["imm_number"] = i
            isel_append(ctx, set_v)
        return r
    if t == ast.EXPR_INDEX:
        let arr = isel_expr(ctx, expr.object)
        let idx = isel_expr(ctx, expr.index)
        let r = isel_vreg(ctx)
        let v = vinst_new(VINST_INDEX)
        v["dest"] = r
        v["src1"] = arr
        v["src2"] = idx
        isel_append(ctx, v)
        return r
    # Default: nil
    let r = isel_vreg(ctx)
    let v = vinst_new(VINST_LOAD_NIL)
    v["dest"] = r
    isel_append(ctx, v)
    return r

# ============================================================================
# Instruction Selection - Statement
# ============================================================================

proc isel_stmt(ctx, stmt):
    if stmt == nil:
        return
    let t = stmt.type
    if t == ast.STMT_PRINT:
        let r = isel_expr(ctx, stmt.expression)
        let v = vinst_new(VINST_PRINT)
        v["src1"] = r
        isel_append(ctx, v)
        return
    if t == ast.STMT_EXPRESSION:
        isel_expr(ctx, stmt.expression)
        return
    if t == ast.STMT_LET:
        let val = isel_expr(ctx, stmt.initializer)
        let name = stmt.name.text
        let v = vinst_new(VINST_STORE_GLOBAL)
        v["src1"] = val
        v["imm_string"] = name
        isel_append(ctx, v)
        return
    if t == ast.STMT_IF:
        let cond = isel_expr(ctx, stmt.condition)
        let then_label = isel_label(ctx)
        let else_label = isel_label(ctx)
        let merge_label = isel_label(ctx)
        let br = vinst_new(VINST_BRANCH)
        br["src1"] = cond
        br["label"] = then_label
        if stmt.else_branch != nil:
            br["label_false"] = else_label
        if stmt.else_branch == nil:
            br["label_false"] = merge_label
        isel_append(ctx, br)
        let tl = vinst_new(VINST_LABEL)
        tl["label"] = then_label
        isel_append(ctx, tl)
        isel_stmt_list(ctx, stmt.then_branch)
        let jmp1 = vinst_new(VINST_JUMP)
        jmp1["label"] = merge_label
        isel_append(ctx, jmp1)
        if stmt.else_branch != nil:
            let el = vinst_new(VINST_LABEL)
            el["label"] = else_label
            isel_append(ctx, el)
            isel_stmt_list(ctx, stmt.else_branch)
            let jmp2 = vinst_new(VINST_JUMP)
            jmp2["label"] = merge_label
            isel_append(ctx, jmp2)
        let ml = vinst_new(VINST_LABEL)
        ml["label"] = merge_label
        isel_append(ctx, ml)
        return
    if t == ast.STMT_WHILE:
        let cond_label = isel_label(ctx)
        let body_label = isel_label(ctx)
        let end_label = isel_label(ctx)
        push(ctx.loop_cond_labels, cond_label)
        push(ctx.loop_end_labels, end_label)
        ctx.loop_depth = ctx.loop_depth + 1
        let jmp0 = vinst_new(VINST_JUMP)
        jmp0["label"] = cond_label
        isel_append(ctx, jmp0)
        let cl = vinst_new(VINST_LABEL)
        cl["label"] = cond_label
        isel_append(ctx, cl)
        let cond = isel_expr(ctx, stmt.condition)
        let br = vinst_new(VINST_BRANCH)
        br["src1"] = cond
        br["label"] = body_label
        br["label_false"] = end_label
        isel_append(ctx, br)
        let bl = vinst_new(VINST_LABEL)
        bl["label"] = body_label
        isel_append(ctx, bl)
        isel_stmt_list(ctx, stmt.body)
        let jmp1 = vinst_new(VINST_JUMP)
        jmp1["label"] = cond_label
        isel_append(ctx, jmp1)
        let el = vinst_new(VINST_LABEL)
        el["label"] = end_label
        isel_append(ctx, el)
        ctx.loop_depth = ctx.loop_depth - 1
        pop(ctx.loop_cond_labels)
        pop(ctx.loop_end_labels)
        return
    if t == ast.STMT_BLOCK:
        isel_stmt_list(ctx, stmt.statements)
        return
    if t == ast.STMT_RETURN:
        let r = isel_expr(ctx, stmt.value)
        let v = vinst_new(VINST_RET)
        v["src1"] = r
        isel_append(ctx, v)
        return
    if t == ast.STMT_FOR:
        let iter = isel_expr(ctx, stmt.iterable)
        let len_reg = isel_vreg(ctx)
        let len_call = vinst_new(VINST_CALL_BUILTIN)
        len_call["dest"] = len_reg
        len_call["func_name"] = "len"
        len_call["call_args"] = [iter]
        len_call["call_arg_count"] = 1
        isel_append(ctx, len_call)
        let idx_reg = isel_vreg(ctx)
        let idx_init = vinst_new(VINST_LOAD_IMM)
        idx_init["dest"] = idx_reg
        idx_init["imm_number"] = 0
        isel_append(ctx, idx_init)
        let var_name = stmt.variable.text
        let init_store = vinst_new(VINST_STORE_GLOBAL)
        init_store["src1"] = idx_reg
        init_store["imm_string"] = "__for_idx__"
        isel_append(ctx, init_store)
        let cond_label = isel_label(ctx)
        let body_label = isel_label(ctx)
        let end_label = isel_label(ctx)
        push(ctx.loop_cond_labels, cond_label)
        push(ctx.loop_end_labels, end_label)
        ctx.loop_depth = ctx.loop_depth + 1
        let jmp0 = vinst_new(VINST_JUMP)
        jmp0["label"] = cond_label
        isel_append(ctx, jmp0)
        let cl = vinst_new(VINST_LABEL)
        cl["label"] = cond_label
        isel_append(ctx, cl)
        let cur_idx = isel_vreg(ctx)
        let load_idx = vinst_new(VINST_LOAD_GLOBAL)
        load_idx["dest"] = cur_idx
        load_idx["imm_string"] = "__for_idx__"
        isel_append(ctx, load_idx)
        let cmp = isel_vreg(ctx)
        let lt_v = vinst_new(VINST_LT)
        lt_v["dest"] = cmp
        lt_v["src1"] = cur_idx
        lt_v["src2"] = len_reg
        isel_append(ctx, lt_v)
        let br = vinst_new(VINST_BRANCH)
        br["src1"] = cmp
        br["label"] = body_label
        br["label_false"] = end_label
        isel_append(ctx, br)
        let bl = vinst_new(VINST_LABEL)
        bl["label"] = body_label
        isel_append(ctx, bl)
        let elem = isel_vreg(ctx)
        let index_v = vinst_new(VINST_INDEX)
        index_v["dest"] = elem
        index_v["src1"] = iter
        index_v["src2"] = cur_idx
        isel_append(ctx, index_v)
        let store_var = vinst_new(VINST_STORE_GLOBAL)
        store_var["src1"] = elem
        store_var["imm_string"] = var_name
        isel_append(ctx, store_var)
        isel_stmt_list(ctx, stmt.body)
        let one_reg = isel_vreg(ctx)
        let one_v = vinst_new(VINST_LOAD_IMM)
        one_v["dest"] = one_reg
        one_v["imm_number"] = 1
        isel_append(ctx, one_v)
        let next_idx = isel_vreg(ctx)
        let add_v = vinst_new(VINST_ADD)
        add_v["dest"] = next_idx
        add_v["src1"] = cur_idx
        add_v["src2"] = one_reg
        isel_append(ctx, add_v)
        let store_idx = vinst_new(VINST_STORE_GLOBAL)
        store_idx["src1"] = next_idx
        store_idx["imm_string"] = "__for_idx__"
        isel_append(ctx, store_idx)
        let jmp1 = vinst_new(VINST_JUMP)
        jmp1["label"] = cond_label
        isel_append(ctx, jmp1)
        let el = vinst_new(VINST_LABEL)
        el["label"] = end_label
        isel_append(ctx, el)
        ctx.loop_depth = ctx.loop_depth - 1
        pop(ctx.loop_cond_labels)
        pop(ctx.loop_end_labels)
        return
    if t == ast.STMT_BREAK:
        if ctx.loop_depth > 0:
            let jmp = vinst_new(VINST_JUMP)
            jmp["label"] = ctx.loop_end_labels[ctx.loop_depth - 1]
            isel_append(ctx, jmp)
        return
    if t == ast.STMT_CONTINUE:
        if ctx.loop_depth > 0:
            let jmp = vinst_new(VINST_JUMP)
            jmp["label"] = ctx.loop_cond_labels[ctx.loop_depth - 1]
            isel_append(ctx, jmp)
        return

proc isel_stmt_list(ctx, head):
    let s = head
    while s != nil:
        isel_stmt(ctx, s)
        s = s.next

# ============================================================================
# Full Instruction Selection Pipeline
# ============================================================================

proc isel_compile(program):
    let ctx = ISelContext()
    isel_stmt_list(ctx, program)
    return ctx

# ============================================================================
# Collect VInst list as array
# ============================================================================

proc collect_vinsts(ctx):
    let result = []
    let v = ctx.head
    while v != nil:
        push(result, v)
        v = v["next"]
    return result

# ============================================================================
# Assembly Text Emission - x86-64
# ============================================================================

proc emit_asm_vinst_x86_64(v):
    let nl = chr(10)
    let pct = chr(37)
    let kind = v["kind"]
    if kind == VINST_LOAD_IMM:
        return "  # v" + str(v["dest"]) + " = number " + str(v["imm_number"]) + nl + "  movsd .LC" + str(v["dest"]) + "(" + pct + "rip), " + pct + "xmm0" + nl + "  call sage_rt_number" + nl + "  movq " + pct + "rax, " + str(-(v["dest"] + 1) * 16) + "(" + pct + "rbp)" + nl + "  movq " + pct + "rdx, " + str(-(v["dest"] + 1) * 16 + 8) + "(" + pct + "rbp)" + nl
    if kind == VINST_PRINT:
        return "  # print v" + str(v["src1"]) + nl + "  movq " + str(-(v["src1"] + 1) * 16) + "(" + pct + "rbp), " + pct + "rdi" + nl + "  movq " + str(-(v["src1"] + 1) * 16 + 8) + "(" + pct + "rbp), " + pct + "rsi" + nl + "  call sage_rt_print" + nl
    if kind == VINST_ADD or kind == VINST_SUB or kind == VINST_MUL or kind == VINST_DIV:
        let fn = "sage_rt_add"
        if kind == VINST_SUB:
            fn = "sage_rt_sub"
        if kind == VINST_MUL:
            fn = "sage_rt_mul"
        if kind == VINST_DIV:
            fn = "sage_rt_div"
        return "  # v" + str(v["dest"]) + " = v" + str(v["src1"]) + " op v" + str(v["src2"]) + nl + "  movq " + str(-(v["src1"] + 1) * 16) + "(" + pct + "rbp), " + pct + "rdi" + nl + "  movq " + str(-(v["src1"] + 1) * 16 + 8) + "(" + pct + "rbp), " + pct + "rsi" + nl + "  movq " + str(-(v["src2"] + 1) * 16) + "(" + pct + "rbp), " + pct + "rdx" + nl + "  movq " + str(-(v["src2"] + 1) * 16 + 8) + "(" + pct + "rbp), " + pct + "rcx" + nl + "  call " + fn + nl + "  movq " + pct + "rax, " + str(-(v["dest"] + 1) * 16) + "(" + pct + "rbp)" + nl + "  movq " + pct + "rdx, " + str(-(v["dest"] + 1) * 16 + 8) + "(" + pct + "rbp)" + nl
    if kind == VINST_CALL:
        return "  # call " + str(v["func_name"]) + nl + "  call sage_fn_" + str(v["func_name"]) + nl + "  movq " + pct + "rax, " + str(-(v["dest"] + 1) * 16) + "(" + pct + "rbp)" + nl + "  movq " + pct + "rdx, " + str(-(v["dest"] + 1) * 16 + 8) + "(" + pct + "rbp)" + nl
    if kind == VINST_LABEL:
        return str(v["label"]) + ":" + nl
    if kind == VINST_JUMP:
        return "  jmp " + str(v["label"]) + nl
    if kind == VINST_RET:
        return "  movq " + str(-(v["src1"] + 1) * 16) + "(" + pct + "rbp), " + pct + "rax" + nl + "  movq " + str(-(v["src1"] + 1) * 16 + 8) + "(" + pct + "rbp), " + pct + "rdx" + nl + "  leave" + nl + "  ret" + nl
    return "  # unhandled vinst " + str(kind) + nl

# ============================================================================
# Assembly Text Emission - aarch64
# ============================================================================

proc emit_asm_vinst_aarch64(v):
    let nl = chr(10)
    let kind = v["kind"]
    if kind == VINST_LOAD_IMM:
        return "  // v" + str(v["dest"]) + " = number " + str(v["imm_number"]) + nl + "  bl sage_rt_number" + nl + "  str x0, [sp, #" + str(v["dest"] * 16) + "]" + nl + "  str x1, [sp, #" + str(v["dest"] * 16 + 8) + "]" + nl
    if kind == VINST_PRINT:
        return "  // print v" + str(v["src1"]) + nl + "  ldr x0, [sp, #" + str(v["src1"] * 16) + "]" + nl + "  ldr x1, [sp, #" + str(v["src1"] * 16 + 8) + "]" + nl + "  bl sage_rt_print" + nl
    if kind == VINST_LABEL:
        return str(v["label"]) + ":" + nl
    if kind == VINST_JUMP:
        return "  b " + str(v["label"]) + nl
    if kind == VINST_RET:
        return "  ldr x0, [sp, #" + str(v["src1"] * 16) + "]" + nl + "  ldr x1, [sp, #" + str(v["src1"] * 16 + 8) + "]" + nl + "  ldp x29, x30, [sp], #256" + nl + "  ret" + nl
    return "  // unhandled vinst " + str(kind) + nl

# ============================================================================
# Assembly Text Emission - rv64
# ============================================================================

proc emit_asm_vinst_rv64(v):
    let nl = chr(10)
    let kind = v["kind"]
    if kind == VINST_LOAD_IMM:
        return "  # v" + str(v["dest"]) + " = number " + str(v["imm_number"]) + nl + "  call sage_rt_number" + nl + "  sd a0, " + str(v["dest"] * 16) + "(sp)" + nl + "  sd a1, " + str(v["dest"] * 16 + 8) + "(sp)" + nl
    if kind == VINST_PRINT:
        return "  # print v" + str(v["src1"]) + nl + "  ld a0, " + str(v["src1"] * 16) + "(sp)" + nl + "  ld a1, " + str(v["src1"] * 16 + 8) + "(sp)" + nl + "  call sage_rt_print" + nl
    if kind == VINST_LABEL:
        return str(v["label"]) + ":" + nl
    if kind == VINST_JUMP:
        return "  j " + str(v["label"]) + nl
    if kind == VINST_RET:
        return "  ld a0, " + str(v["src1"] * 16) + "(sp)" + nl + "  ld a1, " + str(v["src1"] * 16 + 8) + "(sp)" + nl + "  ld ra, 8(sp)" + nl + "  ld s0, 0(sp)" + nl + "  addi sp, sp, 256" + nl + "  ret" + nl
    return "  # unhandled vinst " + str(kind) + nl

# ============================================================================
# Assembly Header / Prologue / Epilogue
# ============================================================================

proc emit_asm_header(target):
    let nl = chr(10)
    let parts = []
    push(parts, "# SageLang assembly output for " + target_name(target) + nl)
    push(parts, "# Generated by sage compiler" + nl + nl)
    if target == TARGET_X86_64:
        push(parts, ".intel_syntax noprefix" + nl)
    push(parts, ".text" + nl)
    push(parts, ".globl main" + nl + nl)
    return join(parts, "")

proc emit_asm_prologue(target, name):
    let nl = chr(10)
    let pct = chr(37)
    let parts = []
    push(parts, name + ":" + nl)
    if target == TARGET_X86_64:
        push(parts, "  push rbp" + nl)
        push(parts, "  mov rbp, rsp" + nl)
        push(parts, "  sub rsp, 256" + nl)
    if target == TARGET_AARCH64:
        push(parts, "  stp x29, x30, [sp, #-256]!" + nl)
        push(parts, "  mov x29, sp" + nl)
    if target == TARGET_RV64:
        push(parts, "  addi sp, sp, -256" + nl)
        push(parts, "  sd ra, 8(sp)" + nl)
        push(parts, "  sd s0, 0(sp)" + nl)
        push(parts, "  addi s0, sp, 256" + nl)
    return join(parts, "")

proc emit_asm_epilogue(target):
    let nl = chr(10)
    let pct = chr(37)
    let parts = []
    if target == TARGET_X86_64:
        push(parts, "  xor eax, eax" + nl)
        push(parts, "  leave" + nl)
        push(parts, "  ret" + nl)
    if target == TARGET_AARCH64:
        push(parts, "  mov w0, #0" + nl)
        push(parts, "  ldp x29, x30, [sp], #256" + nl)
        push(parts, "  ret" + nl)
    if target == TARGET_RV64:
        push(parts, "  li a0, 0" + nl)
        push(parts, "  ld ra, 8(sp)" + nl)
        push(parts, "  ld s0, 0(sp)" + nl)
        push(parts, "  addi sp, sp, 256" + nl)
        push(parts, "  ret" + nl)
    return join(parts, "")

# ============================================================================
# Full Assembly Generation
# ============================================================================

proc compile_to_asm(program, target):
    let ctx = isel_compile(program)
    let parts = []
    push(parts, emit_asm_header(target))
    push(parts, emit_asm_prologue(target, "main"))
    let v = ctx.head
    while v != nil:
        if target == TARGET_X86_64:
            push(parts, emit_asm_vinst_x86_64(v))
        if target == TARGET_AARCH64:
            push(parts, emit_asm_vinst_aarch64(v))
        if target == TARGET_RV64:
            push(parts, emit_asm_vinst_rv64(v))
        v = v["next"]
    push(parts, emit_asm_epilogue(target))
    # Emit string data section
    if ctx.string_pool_count > 0:
        let nl = chr(10)
        push(parts, nl + ".section .rodata" + nl)
        for i in range(ctx.string_pool_count):
            push(parts, ".LC" + str(i) + ":" + nl)
            push(parts, "  .asciz " + chr(34) + ctx.string_pool[i] + chr(34) + nl)
    return join(parts, "")
