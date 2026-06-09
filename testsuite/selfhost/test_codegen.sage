gc_disable()
# Tests for codegen.sage (instruction selection + assembly text emission)
import token
import ast
import codegen

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

# ============================================================================
# VInst Kind Constants
# ============================================================================

assert_eq(codegen.VINST_LOAD_IMM, 0, "VINST_LOAD_IMM = 0")
assert_eq(codegen.VINST_PRINT, 20, "VINST_PRINT = 20")
assert_eq(codegen.VINST_LABEL, 26, "VINST_LABEL = 26")
assert_eq(codegen.VINST_JUMP, 25, "VINST_JUMP = 25")

# ============================================================================
# Target Constants
# ============================================================================

assert_eq(codegen.TARGET_X86_64, 0, "TARGET_X86_64 = 0")
assert_eq(codegen.TARGET_AARCH64, 1, "TARGET_AARCH64 = 1")
assert_eq(codegen.TARGET_RV64, 2, "TARGET_RV64 = 2")
assert_eq(codegen.target_name(codegen.TARGET_X86_64), "x86_64", "target name x86_64")
assert_eq(codegen.target_name(codegen.TARGET_AARCH64), "aarch64", "target name aarch64")
assert_eq(codegen.target_name(codegen.TARGET_RV64), "rv64", "target name rv64")

# ============================================================================
# VInst Node
# ============================================================================

let v = codegen.vinst_new(codegen.VINST_LOAD_IMM)
assert_eq(v["kind"], codegen.VINST_LOAD_IMM, "vinst kind")
assert_eq(v["dest"], -1, "vinst default dest")
assert_eq(v["src1"], -1, "vinst default src1")
assert_eq(v["src2"], -1, "vinst default src2")
assert_eq(v["next"], nil, "vinst default next")
assert_eq(v["func_name"], nil, "vinst default func_name")

# ============================================================================
# VInst Kind Names
# ============================================================================

assert_eq(codegen.vinst_kind_name(codegen.VINST_LOAD_IMM), "LOAD_IMM", "kind name LOAD_IMM")
assert_eq(codegen.vinst_kind_name(codegen.VINST_ADD), "ADD", "kind name ADD")
assert_eq(codegen.vinst_kind_name(codegen.VINST_PRINT), "PRINT", "kind name PRINT")
assert_eq(codegen.vinst_kind_name(codegen.VINST_CALL), "CALL", "kind name CALL")
assert_eq(codegen.vinst_kind_name(codegen.VINST_LABEL), "LABEL", "kind name LABEL")
assert_eq(codegen.vinst_kind_name(codegen.VINST_BRANCH), "BRANCH", "kind name BRANCH")
assert_eq(codegen.vinst_kind_name(999), "UNKNOWN", "kind name unknown")

# ============================================================================
# ISelContext
# ============================================================================

let ctx = codegen.ISelContext()
assert_eq(ctx.next_vreg, 0, "ctx initial vreg")
assert_eq(ctx.next_label, 0, "ctx initial label")
assert_eq(ctx.head, nil, "ctx initial head")
assert_eq(ctx.tail, nil, "ctx initial tail")
assert_eq(ctx.loop_depth, 0, "ctx initial loop_depth")

# --- isel_vreg ---
let r0 = codegen.isel_vreg(ctx)
assert_eq(r0, 0, "isel_vreg first")
let r1 = codegen.isel_vreg(ctx)
assert_eq(r1, 1, "isel_vreg second")

# --- isel_label ---
let l0 = codegen.isel_label(ctx)
assert_eq(l0, ".L0", "isel_label first")
let l1 = codegen.isel_label(ctx)
assert_eq(l1, ".L1", "isel_label second")

# --- isel_add_string ---
let s0 = codegen.isel_add_string(ctx, "hello")
assert_eq(s0, 0, "isel_add_string first")
assert_eq(ctx.string_pool_count, 1, "string_pool_count after 1")
assert_eq(ctx.string_pool[0], "hello", "string_pool value")

# --- isel_append ---
let ctx2 = codegen.ISelContext()
let v1 = codegen.vinst_new(codegen.VINST_LOAD_IMM)
v1["dest"] = 0
codegen.isel_append(ctx2, v1)
assert_true(ctx2.head != nil, "append sets head")
assert_true(ctx2.tail != nil, "append sets tail")
assert_eq(ctx2.head["kind"], codegen.VINST_LOAD_IMM, "head is correct")

let v2 = codegen.vinst_new(codegen.VINST_PRINT)
v2["src1"] = 0
codegen.isel_append(ctx2, v2)
assert_eq(ctx2.head["kind"], codegen.VINST_LOAD_IMM, "head unchanged after second append")
assert_eq(ctx2.tail["kind"], codegen.VINST_PRINT, "tail is second node")

# ============================================================================
# Expression Instruction Selection
# ============================================================================

# --- Number ---
let ctx3 = codegen.ISelContext()
let r_num = codegen.isel_expr(ctx3, ast.number_expr(42))
assert_eq(r_num, 0, "isel number reg")
assert_eq(ctx3.head["kind"], codegen.VINST_LOAD_IMM, "number -> LOAD_IMM")
assert_eq(ctx3.head["dest"], 0, "number dest = 0")
assert_eq(ctx3.head["imm_number"], 42, "number imm = 42")

# --- String ---
let ctx4 = codegen.ISelContext()
let r_str = codegen.isel_expr(ctx4, ast.string_expr("hello"))
assert_eq(ctx4.head["kind"], codegen.VINST_LOAD_STRING, "string -> LOAD_STRING")
assert_eq(ctx4.head["imm_string"], "hello", "string imm = hello")
assert_eq(ctx4.string_pool_count, 1, "string added to pool")

# --- Bool ---
let ctx5 = codegen.ISelContext()
codegen.isel_expr(ctx5, ast.bool_expr(true))
assert_eq(ctx5.head["kind"], codegen.VINST_LOAD_BOOL, "bool -> LOAD_BOOL")
assert_eq(ctx5.head["imm_bool"], true, "bool imm = true")

# --- Nil ---
let ctx6 = codegen.ISelContext()
codegen.isel_expr(ctx6, ast.nil_expr())
assert_eq(ctx6.head["kind"], codegen.VINST_LOAD_NIL, "nil -> LOAD_NIL")

# --- Nil expr (null) ---
let ctx6b = codegen.ISelContext()
codegen.isel_expr(ctx6b, nil)
assert_eq(ctx6b.head["kind"], codegen.VINST_LOAD_NIL, "null expr -> LOAD_NIL")

# --- Variable ---
let ctx7 = codegen.ISelContext()
codegen.isel_expr(ctx7, ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "x", 1)))
assert_eq(ctx7.head["kind"], codegen.VINST_LOAD_GLOBAL, "var -> LOAD_GLOBAL")
assert_eq(ctx7.head["imm_string"], "x", "var name = x")

# --- Binary: add ---
let ctx8 = codegen.ISelContext()
let bin = ast.binary_expr(ast.number_expr(1), token.Token(token.TOKEN_PLUS, "+", 1), ast.number_expr(2))
codegen.isel_expr(ctx8, bin)
let vinsts = codegen.collect_vinsts(ctx8)
assert_eq(len(vinsts), 3, "binary produces 3 vinsts")
assert_eq(vinsts[0]["kind"], codegen.VINST_LOAD_IMM, "binary first = LOAD_IMM")
assert_eq(vinsts[1]["kind"], codegen.VINST_LOAD_IMM, "binary second = LOAD_IMM")
assert_eq(vinsts[2]["kind"], codegen.VINST_ADD, "binary third = ADD")
assert_eq(vinsts[2]["src1"], 0, "add src1 = 0")
assert_eq(vinsts[2]["src2"], 1, "add src2 = 1")

# --- Binary: subtract ---
let ctx8b = codegen.ISelContext()
let bin_sub = ast.binary_expr(ast.number_expr(5), token.Token(token.TOKEN_MINUS, "-", 1), ast.number_expr(3))
codegen.isel_expr(ctx8b, bin_sub)
let vinsts_sub = codegen.collect_vinsts(ctx8b)
assert_eq(vinsts_sub[2]["kind"], codegen.VINST_SUB, "sub -> VINST_SUB")

# --- Binary: compare ---
let ctx8c = codegen.ISelContext()
let bin_lt = ast.binary_expr(ast.number_expr(1), token.Token(token.TOKEN_LT, "<", 1), ast.number_expr(2))
codegen.isel_expr(ctx8c, bin_lt)
let vinsts_lt = codegen.collect_vinsts(ctx8c)
assert_eq(vinsts_lt[2]["kind"], codegen.VINST_LT, "lt -> VINST_LT")

# --- Call: builtin ---
let ctx9 = codegen.ISelContext()
let call_len = ast.call_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "len", 1)), [ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "arr", 1))])
codegen.isel_expr(ctx9, call_len)
let vinsts_call = codegen.collect_vinsts(ctx9)
let last_call = vinsts_call[len(vinsts_call) - 1]
assert_eq(last_call["kind"], codegen.VINST_CALL_BUILTIN, "builtin call -> CALL_BUILTIN")
assert_eq(last_call["func_name"], "len", "builtin func_name = len")

# --- Call: user function ---
let ctx10 = codegen.ISelContext()
let call_user = ast.call_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "myfunc", 1)), [ast.number_expr(1)])
codegen.isel_expr(ctx10, call_user)
let vinsts_user = codegen.collect_vinsts(ctx10)
let last_user = vinsts_user[len(vinsts_user) - 1]
assert_eq(last_user["kind"], codegen.VINST_CALL, "user call -> CALL")
assert_eq(last_user["func_name"], "myfunc", "user func_name = myfunc")

# --- Array ---
let ctx11 = codegen.ISelContext()
let arr_e = ast.array_expr([ast.number_expr(1), ast.number_expr(2)])
codegen.isel_expr(ctx11, arr_e)
let vinsts_arr = codegen.collect_vinsts(ctx11)
# Should have: LOAD_IMM, LOAD_IMM, ARRAY_NEW, ARRAY_SET, ARRAY_SET
let found_array_new = false
let found_array_set = false
for i in range(len(vinsts_arr)):
    if vinsts_arr[i]["kind"] == codegen.VINST_ARRAY_NEW:
        found_array_new = true
    if vinsts_arr[i]["kind"] == codegen.VINST_ARRAY_SET:
        found_array_set = true
assert_true(found_array_new, "array has ARRAY_NEW")
assert_true(found_array_set, "array has ARRAY_SET")

# --- Index ---
let ctx12 = codegen.ISelContext()
let idx_e = ast.index_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "arr", 1)), ast.number_expr(0))
codegen.isel_expr(ctx12, idx_e)
let vinsts_idx = codegen.collect_vinsts(ctx12)
let last_idx = vinsts_idx[len(vinsts_idx) - 1]
assert_eq(last_idx["kind"], codegen.VINST_INDEX, "index -> INDEX")

# ============================================================================
# Statement Instruction Selection
# ============================================================================

# --- Print ---
let ctx20 = codegen.ISelContext()
codegen.isel_stmt(ctx20, ast.print_stmt(ast.number_expr(42)))
let vs20 = codegen.collect_vinsts(ctx20)
assert_eq(vs20[0]["kind"], codegen.VINST_LOAD_IMM, "print: first = LOAD_IMM")
assert_eq(vs20[1]["kind"], codegen.VINST_PRINT, "print: second = PRINT")

# --- Let ---
let ctx21 = codegen.ISelContext()
codegen.isel_stmt(ctx21, ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "x", 1), ast.number_expr(10)))
let vs21 = codegen.collect_vinsts(ctx21)
assert_eq(vs21[1]["kind"], codegen.VINST_STORE_GLOBAL, "let: STORE_GLOBAL")
assert_eq(vs21[1]["imm_string"], "x", "let: stores to x")

# --- Return ---
let ctx22 = codegen.ISelContext()
codegen.isel_stmt(ctx22, ast.return_stmt(ast.number_expr(5)))
let vs22 = codegen.collect_vinsts(ctx22)
let last22 = vs22[len(vs22) - 1]
assert_eq(last22["kind"], codegen.VINST_RET, "return: RET")

# --- If (no else) ---
let ctx23 = codegen.ISelContext()
codegen.isel_stmt(ctx23, ast.if_stmt(ast.bool_expr(true), ast.print_stmt(ast.number_expr(1)), nil))
let vs23 = codegen.collect_vinsts(ctx23)
let found_branch = false
let found_label = false
let found_jump = false
for i in range(len(vs23)):
    if vs23[i]["kind"] == codegen.VINST_BRANCH:
        found_branch = true
    if vs23[i]["kind"] == codegen.VINST_LABEL:
        found_label = true
    if vs23[i]["kind"] == codegen.VINST_JUMP:
        found_jump = true
assert_true(found_branch, "if: has BRANCH")
assert_true(found_label, "if: has LABEL")
assert_true(found_jump, "if: has JUMP")

# --- If/else ---
let ctx24 = codegen.ISelContext()
codegen.isel_stmt(ctx24, ast.if_stmt(ast.bool_expr(true), ast.print_stmt(ast.number_expr(1)), ast.print_stmt(ast.number_expr(2))))
let vs24 = codegen.collect_vinsts(ctx24)
let label_count = 0
for i in range(len(vs24)):
    if vs24[i]["kind"] == codegen.VINST_LABEL:
        label_count = label_count + 1
assert_eq(label_count, 3, "if/else: 3 labels (then, else, merge)")

# --- While ---
let ctx25 = codegen.ISelContext()
codegen.isel_stmt(ctx25, ast.while_stmt(ast.bool_expr(true), ast.print_stmt(ast.number_expr(1))))
let vs25 = codegen.collect_vinsts(ctx25)
let jump_count = 0
for i in range(len(vs25)):
    if vs25[i]["kind"] == codegen.VINST_JUMP:
        jump_count = jump_count + 1
assert_true(jump_count >= 2, "while: at least 2 jumps (to cond, back to cond)")

# --- Break ---
let ctx26 = codegen.ISelContext()
push(ctx26.loop_cond_labels, ".L5")
push(ctx26.loop_end_labels, ".L6")
ctx26.loop_depth = 1
codegen.isel_stmt(ctx26, ast.break_stmt())
let vs26 = codegen.collect_vinsts(ctx26)
assert_eq(vs26[0]["kind"], codegen.VINST_JUMP, "break: JUMP")
assert_eq(vs26[0]["label"], ".L6", "break: jumps to end label")

# --- Continue ---
let ctx27 = codegen.ISelContext()
push(ctx27.loop_cond_labels, ".L10")
push(ctx27.loop_end_labels, ".L11")
ctx27.loop_depth = 1
codegen.isel_stmt(ctx27, ast.continue_stmt())
let vs27 = codegen.collect_vinsts(ctx27)
assert_eq(vs27[0]["kind"], codegen.VINST_JUMP, "continue: JUMP")
assert_eq(vs27[0]["label"], ".L10", "continue: jumps to cond label")

# ============================================================================
# Full Compilation Pipeline
# ============================================================================

let prog = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "x", 1), ast.number_expr(42))
let print_s = ast.print_stmt(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "x", 1)))
prog.next = print_s
let full_ctx = codegen.isel_compile(prog)
let full_vs = codegen.collect_vinsts(full_ctx)
assert_true(len(full_vs) >= 3, "full pipeline produces instructions")
# Should have: LOAD_IMM(42), STORE_GLOBAL(x), LOAD_GLOBAL(x), PRINT
let found_store = false
let found_print = false
for i in range(len(full_vs)):
    if full_vs[i]["kind"] == codegen.VINST_STORE_GLOBAL:
        found_store = true
    if full_vs[i]["kind"] == codegen.VINST_PRINT:
        found_print = true
assert_true(found_store, "full: has STORE_GLOBAL")
assert_true(found_print, "full: has PRINT")

# ============================================================================
# Assembly Text Generation
# ============================================================================

# --- x86-64 ---
let asm_x86 = codegen.compile_to_asm(prog, codegen.TARGET_X86_64)
assert_true(contains(asm_x86, ".intel_syntax"), "x86: intel syntax")
assert_true(contains(asm_x86, ".text"), "x86: text section")
assert_true(contains(asm_x86, ".globl main"), "x86: globl main")
assert_true(contains(asm_x86, "main:"), "x86: main label")
assert_true(contains(asm_x86, "push rbp"), "x86: prologue push rbp")
assert_true(contains(asm_x86, "leave"), "x86: epilogue leave")
assert_true(contains(asm_x86, "ret"), "x86: epilogue ret")
assert_true(contains(asm_x86, "sage_rt"), "x86: calls runtime")

# --- aarch64 ---
let asm_aarch64 = codegen.compile_to_asm(prog, codegen.TARGET_AARCH64)
assert_true(contains(asm_aarch64, "aarch64"), "aarch64: target name")
assert_true(contains(asm_aarch64, ".globl main"), "aarch64: globl main")
assert_true(contains(asm_aarch64, "stp x29"), "aarch64: prologue stp")
assert_true(contains(asm_aarch64, "ldp x29"), "aarch64: epilogue ldp")

# --- rv64 ---
let asm_rv64 = codegen.compile_to_asm(prog, codegen.TARGET_RV64)
assert_true(contains(asm_rv64, "rv64"), "rv64: target name")
assert_true(contains(asm_rv64, "addi sp"), "rv64: prologue addi sp")
assert_true(contains(asm_rv64, "sd ra"), "rv64: saves ra")

# ============================================================================
# Assembly Header
# ============================================================================

let hdr_x86 = codegen.emit_asm_header(codegen.TARGET_X86_64)
assert_true(contains(hdr_x86, "x86_64"), "header x86: target name")
assert_true(contains(hdr_x86, ".intel_syntax"), "header x86: intel syntax")

let hdr_arm = codegen.emit_asm_header(codegen.TARGET_AARCH64)
assert_true(contains(hdr_arm, "aarch64"), "header aarch64: target name")
assert_true(not contains(hdr_arm, ".intel_syntax"), "header aarch64: no intel syntax")

# ============================================================================
# Assembly Prologue / Epilogue
# ============================================================================

let pro_x86 = codegen.emit_asm_prologue(codegen.TARGET_X86_64, "test_fn")
assert_true(contains(pro_x86, "test_fn:"), "prologue x86: label")
assert_true(contains(pro_x86, "push rbp"), "prologue x86: push rbp")
assert_true(contains(pro_x86, "sub rsp, 256"), "prologue x86: sub rsp")

let epi_x86 = codegen.emit_asm_epilogue(codegen.TARGET_X86_64)
assert_true(contains(epi_x86, "xor eax, eax"), "epilogue x86: xor eax")
assert_true(contains(epi_x86, "ret"), "epilogue x86: ret")

# --- String data section ---
let str_prog = ast.expr_stmt(ast.string_expr("hello"))
let asm_with_str = codegen.compile_to_asm(str_prog, codegen.TARGET_X86_64)
assert_true(contains(asm_with_str, ".section .rodata"), "string: rodata section")
assert_true(contains(asm_with_str, ".asciz"), "string: asciz directive")
assert_true(contains(asm_with_str, "hello"), "string: contains hello")

# ============================================================================
# For statement isel
# ============================================================================

let for_body = ast.print_stmt(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "i", 1)))
let for_s = ast.for_stmt(token.Token(token.TOKEN_IDENTIFIER, "i", 1), ast.call_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "range", 1)), [ast.number_expr(3)]), for_body)
let for_ctx = codegen.isel_compile(for_s)
let for_vs = codegen.collect_vinsts(for_ctx)
let for_has_branch = false
let for_has_idx = false
for i in range(len(for_vs)):
    if for_vs[i]["kind"] == codegen.VINST_BRANCH:
        for_has_branch = true
    if for_vs[i]["kind"] == codegen.VINST_INDEX:
        for_has_idx = true
assert_true(for_has_branch, "for: has BRANCH")
assert_true(for_has_idx, "for: has INDEX for element access")

print ""
print "Codegen tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All codegen tests passed!"
