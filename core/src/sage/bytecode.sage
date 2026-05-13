gc_disable()
# ============================================================================
# bytecode.sage - Self-hosted VM artifact emitter
#
# Emits the same strict AOT artifact format as src/vm/program.c:
#   SAGEBC1
#   functions N
#   function
#   params P
#   param <len>
#   <hex-bytes>
#   constants M
#   number <value>
#   string <len>
#   <hex-bytes>
#   code <len>
#   <hex-bytes>
#   endfunction
#   chunks N
#   chunk
#   ...
#   endchunk
# ============================================================================

import token
import ast
import stdlib

let NL = chr(10)
let HEX_DIGITS = "0123456789abcdef"
let last_error = ""

# Opcode values must stay in lockstep with src/vm/bytecode.h.
let BC_OP_CONSTANT = 0
let BC_OP_NIL = 1
let BC_OP_TRUE = 2
let BC_OP_FALSE = 3
let BC_OP_POP = 4
let BC_OP_GET_GLOBAL = 5
let BC_OP_DEFINE_GLOBAL = 6
let BC_OP_SET_GLOBAL = 7
let BC_OP_DEFINE_FUNCTION = 8
let BC_OP_GET_PROPERTY = 9
let BC_OP_SET_PROPERTY = 10
let BC_OP_GET_INDEX = 11
let BC_OP_SET_INDEX = 12
let BC_OP_SLICE = 13
let BC_OP_ADD = 14
let BC_OP_SUB = 15
let BC_OP_MUL = 16
let BC_OP_DIV = 17
let BC_OP_MOD = 18
let BC_OP_NEGATE = 19
let BC_OP_EQUAL = 20
let BC_OP_NOT_EQUAL = 21
let BC_OP_GREATER = 22
let BC_OP_GREATER_EQUAL = 23
let BC_OP_LESS = 24
let BC_OP_LESS_EQUAL = 25
let BC_OP_BIT_AND = 26
let BC_OP_BIT_OR = 27
let BC_OP_BIT_XOR = 28
let BC_OP_BIT_NOT = 29
let BC_OP_SHIFT_LEFT = 30
let BC_OP_SHIFT_RIGHT = 31
let BC_OP_NOT = 32
let BC_OP_TRUTHY = 33
let BC_OP_JUMP = 34
let BC_OP_JUMP_IF_FALSE = 35
let BC_OP_CALL = 36
let BC_OP_CALL_METHOD = 37
let BC_OP_ARRAY = 38
let BC_OP_TUPLE = 39
let BC_OP_DICT = 40
let BC_OP_PRINT = 41
let BC_OP_EXEC_AST_STMT = 42
let BC_OP_RETURN = 43
let BC_OP_PUSH_ENV = 44
let BC_OP_POP_ENV = 45
let BC_OP_DUP = 46
let BC_OP_ARRAY_LEN = 47

proc set_error(message):
    last_error = message
    return false

proc get_error():
    return last_error

proc new_chunk():
    let chunk = {}
    chunk["code"] = []
    chunk["constants"] = []
    return chunk

proc new_program():
    let program = {}
    program["chunks"] = []
    program["functions"] = []
    return program

proc current_offset(chunk):
    return len(chunk["code"])

proc emit_op(chunk, op):
    push(chunk["code"], op)
    return true

proc emit_u8(chunk, value):
    push(chunk["code"], value & 255)
    return true

proc emit_u16(chunk, value):
    push(chunk["code"], (value >> 8) & 255)
    push(chunk["code"], value & 255)
    return true

proc add_constant(chunk, value):
    push(chunk["constants"], value)
    return len(chunk["constants"]) - 1

proc number_constant(value, text):
    let constant = {}
    constant["kind"] = "number"
    constant["value"] = value
    constant["text"] = text
    return constant

proc canonical_number_text(expr):
    if len(expr.text) >= 2 and expr.text[0] == "0" and (expr.text[1] == "b" or expr.text[1] == "B"):
        return format_int_constant(expr.value)
    return expr.text

proc emit_constant(chunk, value):
    let index = add_constant(chunk, value)
    if index > 65535:
        return set_error("Bytecode constant pool exceeded 65535 entries.")
    emit_op(chunk, BC_OP_CONSTANT)
    emit_u16(chunk, index)
    return true

proc emit_number_constant(chunk, expr):
    return emit_constant(chunk, number_constant(expr.value, canonical_number_text(expr)))

proc emit_name_op(chunk, op, tok):
    let index = add_constant(chunk, tok.text)
    if index > 65535:
        return set_error("Bytecode name pool exceeded 65535 entries.")
    emit_op(chunk, op)
    emit_u16(chunk, index)
    return true

proc emit_define_function(chunk, tok, function_index):
    let name_index = add_constant(chunk, tok.text)
    if name_index > 65535 or function_index > 65535:
        return set_error("Bytecode function table exceeded 65535 entries.")
    emit_op(chunk, BC_OP_DEFINE_FUNCTION)
    emit_u16(chunk, name_index)
    emit_u16(chunk, function_index)
    return true

proc emit_dup(chunk, distance):
    emit_op(chunk, BC_OP_DUP)
    emit_u8(chunk, distance)
    return true

proc emit_jump(chunk, op):
    emit_op(chunk, op)
    let patch_location = current_offset(chunk)
    emit_u16(chunk, 0)
    return patch_location

proc patch_jump(chunk, patch_location, target):
    if patch_location < 0 or patch_location + 1 >= len(chunk["code"]):
        return set_error("Invalid jump patch location.")
    chunk["code"][patch_location] = (target >> 8) & 255
    chunk["code"][patch_location + 1] = target & 255
    return true

proc stmt_requires_ast_fallback(stmt, allow_return):
    if stmt == nil:
        return false

    if stmt.type == ast.STMT_BREAK or stmt.type == ast.STMT_CONTINUE or stmt.type == ast.STMT_YIELD:
        return true

    if stmt.type == ast.STMT_RETURN:
        return not allow_return

    if stmt.type == ast.STMT_BLOCK:
        let inner = stmt.statements
        while inner != nil:
            if stmt_requires_ast_fallback(inner, allow_return):
                return true
            inner = inner.next
        return false

    if stmt.type == ast.STMT_IF:
        return stmt_requires_ast_fallback(stmt.then_branch, allow_return) or stmt_requires_ast_fallback(stmt.else_branch, allow_return)

    if stmt.type == ast.STMT_WHILE:
        return stmt_requires_ast_fallback(stmt.body, allow_return)

    if stmt.type == ast.STMT_FOR:
        return stmt_requires_ast_fallback(stmt.body, allow_return)

    if stmt.type == ast.STMT_TRY:
        if stmt_requires_ast_fallback(stmt.try_block, allow_return) or stmt_requires_ast_fallback(stmt.finally_block, allow_return):
            return true
        for clause in stmt.catches:
            if stmt_requires_ast_fallback(clause.body, allow_return):
                return true
        return false

    if stmt.type == ast.STMT_PROC or stmt.type == ast.STMT_CLASS:
        return false

    if stmt.type == ast.STMT_ASYNC_PROC:
        return true

    return false

proc unsupported_stmt():
    return set_error("Statement requires AST fallback and cannot be emitted as a compiled VM artifact yet.")

proc compile_short_circuit(chunk, binary):
    if not compile_expr(chunk, binary.left):
        return false

    if binary.op.type == token.TOKEN_OR:
        let jump_false = emit_jump(chunk, BC_OP_JUMP_IF_FALSE)
        emit_op(chunk, BC_OP_POP)
        emit_op(chunk, BC_OP_TRUE)
        let end_jump = emit_jump(chunk, BC_OP_JUMP)
        patch_jump(chunk, jump_false, current_offset(chunk))
        emit_op(chunk, BC_OP_POP)
        if not compile_expr(chunk, binary.right):
            return false
        emit_op(chunk, BC_OP_TRUTHY)
        return patch_jump(chunk, end_jump, current_offset(chunk))

    let jump_false = emit_jump(chunk, BC_OP_JUMP_IF_FALSE)
    emit_op(chunk, BC_OP_POP)
    if not compile_expr(chunk, binary.right):
        return false
    emit_op(chunk, BC_OP_TRUTHY)
    let end_jump = emit_jump(chunk, BC_OP_JUMP)
    patch_jump(chunk, jump_false, current_offset(chunk))
    emit_op(chunk, BC_OP_POP)
    emit_op(chunk, BC_OP_FALSE)
    return patch_jump(chunk, end_jump, current_offset(chunk))

proc compile_expr(chunk, expr):
    if expr == nil:
        emit_op(chunk, BC_OP_NIL)
        return true

    if expr.type == ast.EXPR_NUMBER:
        return emit_number_constant(chunk, expr)

    if expr.type == ast.EXPR_STRING:
        return emit_constant(chunk, expr.value)

    if expr.type == ast.EXPR_BOOL:
        if expr.value:
            emit_op(chunk, BC_OP_TRUE)
        else:
            emit_op(chunk, BC_OP_FALSE)
        return true

    if expr.type == ast.EXPR_NIL:
        emit_op(chunk, BC_OP_NIL)
        return true

    if expr.type == ast.EXPR_VARIABLE:
        return emit_name_op(chunk, BC_OP_GET_GLOBAL, expr.name)

    if expr.type == ast.EXPR_ARRAY:
        for i in range(len(expr.elements)):
            if not compile_expr(chunk, expr.elements[i]):
                return false
        emit_op(chunk, BC_OP_ARRAY)
        emit_u16(chunk, expr.count)
        return true

    if expr.type == ast.EXPR_TUPLE:
        for i in range(len(expr.elements)):
            if not compile_expr(chunk, expr.elements[i]):
                return false
        emit_op(chunk, BC_OP_TUPLE)
        emit_u16(chunk, expr.count)
        return true

    if expr.type == ast.EXPR_DICT:
        for i in range(len(expr.keys)):
            if not emit_constant(chunk, expr.keys[i]):
                return false
            if not compile_expr(chunk, expr.values[i]):
                return false
        emit_op(chunk, BC_OP_DICT)
        emit_u16(chunk, expr.count)
        return true

    if expr.type == ast.EXPR_INDEX:
        return compile_expr(chunk, expr.object) and compile_expr(chunk, expr.index) and emit_op(chunk, BC_OP_GET_INDEX)

    if expr.type == ast.EXPR_INDEX_SET:
        return compile_expr(chunk, expr.object) and compile_expr(chunk, expr.index) and compile_expr(chunk, expr.value) and emit_op(chunk, BC_OP_SET_INDEX)

    if expr.type == ast.EXPR_SLICE:
        if not compile_expr(chunk, expr.object):
            return false
        if expr.start != nil:
            if not compile_expr(chunk, expr.start):
                return false
        else:
            emit_op(chunk, BC_OP_NIL)
        if expr.end != nil:
            if not compile_expr(chunk, expr.end):
                return false
        else:
            emit_op(chunk, BC_OP_NIL)
        emit_op(chunk, BC_OP_SLICE)
        return true

    if expr.type == ast.EXPR_GET:
        return compile_expr(chunk, expr.object) and emit_name_op(chunk, BC_OP_GET_PROPERTY, expr.property)

    if expr.type == ast.EXPR_SET:
        if expr.object == nil:
            return compile_expr(chunk, expr.value) and emit_name_op(chunk, BC_OP_SET_GLOBAL, expr.property)
        return compile_expr(chunk, expr.object) and compile_expr(chunk, expr.value) and emit_name_op(chunk, BC_OP_SET_PROPERTY, expr.property)

    if expr.type == ast.EXPR_CALL:
        if expr.callee.type == ast.EXPR_GET:
            let get_expr = expr.callee
            if not compile_expr(chunk, get_expr.object):
                return false
            for i in range(len(expr.args)):
                if not compile_expr(chunk, expr.args[i]):
                    return false
            let name_index = add_constant(chunk, get_expr.property.text)
            if name_index > 65535 or expr.arg_count > 255:
                return set_error("Method call operand limit exceeded.")
            emit_op(chunk, BC_OP_CALL_METHOD)
            emit_u16(chunk, name_index)
            emit_u8(chunk, expr.arg_count)
            return true

        if not compile_expr(chunk, expr.callee):
            return false
        for i in range(len(expr.args)):
            if not compile_expr(chunk, expr.args[i]):
                return false
        if expr.arg_count > 255:
            return set_error("Call argument count exceeded 255.")
        emit_op(chunk, BC_OP_CALL)
        emit_u8(chunk, expr.arg_count)
        return true

    if expr.type == ast.EXPR_BINARY:
        let binary = expr
        if binary.op.type == token.TOKEN_OR or binary.op.type == token.TOKEN_AND:
            return compile_short_circuit(chunk, binary)

        if not compile_expr(chunk, binary.left):
            return false

        if binary.op.type == token.TOKEN_NOT:
            emit_op(chunk, BC_OP_NOT)
            return true

        if binary.op.type == token.TOKEN_TILDE:
            emit_op(chunk, BC_OP_BIT_NOT)
            return true

        if binary.right == nil:
            return set_error("Unsupported unary bytecode expression.")

        if not compile_expr(chunk, binary.right):
            return false

        if binary.op.type == token.TOKEN_PLUS:
            emit_op(chunk, BC_OP_ADD)
            return true
        if binary.op.type == token.TOKEN_MINUS:
            emit_op(chunk, BC_OP_SUB)
            return true
        if binary.op.type == token.TOKEN_STAR:
            emit_op(chunk, BC_OP_MUL)
            return true
        if binary.op.type == token.TOKEN_SLASH:
            emit_op(chunk, BC_OP_DIV)
            return true
        if binary.op.type == token.TOKEN_PERCENT:
            emit_op(chunk, BC_OP_MOD)
            return true
        if binary.op.type == token.TOKEN_EQ:
            emit_op(chunk, BC_OP_EQUAL)
            return true
        if binary.op.type == token.TOKEN_NEQ:
            emit_op(chunk, BC_OP_NOT_EQUAL)
            return true
        if binary.op.type == token.TOKEN_GT:
            emit_op(chunk, BC_OP_GREATER)
            return true
        if binary.op.type == token.TOKEN_GTE:
            emit_op(chunk, BC_OP_GREATER_EQUAL)
            return true
        if binary.op.type == token.TOKEN_LT:
            emit_op(chunk, BC_OP_LESS)
            return true
        if binary.op.type == token.TOKEN_LTE:
            emit_op(chunk, BC_OP_LESS_EQUAL)
            return true
        if binary.op.type == token.TOKEN_AMP:
            emit_op(chunk, BC_OP_BIT_AND)
            return true
        if binary.op.type == token.TOKEN_PIPE:
            emit_op(chunk, BC_OP_BIT_OR)
            return true
        if binary.op.type == token.TOKEN_CARET:
            emit_op(chunk, BC_OP_BIT_XOR)
            return true
        if binary.op.type == token.TOKEN_LSHIFT:
            emit_op(chunk, BC_OP_SHIFT_LEFT)
            return true
        if binary.op.type == token.TOKEN_RSHIFT:
            emit_op(chunk, BC_OP_SHIFT_RIGHT)
            return true

        return set_error("Unsupported binary expression in bytecode mode.")

    if expr.type == ast.EXPR_AWAIT:
        return set_error("await expressions are not compiled to bytecode yet.")

    return set_error("Unsupported expression in bytecode mode.")

proc compile_block(program, chunk, stmt, allow_return):
    let inner = stmt.statements
    while inner != nil:
        if not compile_stmt(program, chunk, inner, false, allow_return):
            return false
        inner = inner.next
    return true

proc compile_proc_function(program, stmt):
    let function = {}
    function["params"] = []
    for i in range(stmt.param_count):
        push(function["params"], stmt.params[i].text)
    function["chunk"] = new_chunk()

    if not compile_stmt(program, function["chunk"], stmt.body, false, true):
        return -1

    emit_op(function["chunk"], BC_OP_NIL)
    emit_op(function["chunk"], BC_OP_RETURN)
    push(program["functions"], function)
    return len(program["functions"]) - 1

proc compile_stmt(program, chunk, stmt, want_result, allow_return):
    if stmt == nil:
        if want_result:
            emit_op(chunk, BC_OP_NIL)
        return true

    if stmt_requires_ast_fallback(stmt, allow_return):
        return unsupported_stmt()

    if stmt.type == ast.STMT_PRINT:
        if not compile_expr(chunk, stmt.expression):
            return false
        emit_op(chunk, BC_OP_PRINT)
        if want_result:
            emit_op(chunk, BC_OP_NIL)
        return true

    if stmt.type == ast.STMT_LET:
        if stmt.initializer != nil:
            if not compile_expr(chunk, stmt.initializer):
                return false
        else:
            emit_op(chunk, BC_OP_NIL)
        emit_name_op(chunk, BC_OP_DEFINE_GLOBAL, stmt.name)
        if want_result:
            emit_op(chunk, BC_OP_NIL)
        return true

    if stmt.type == ast.STMT_PROC:
        let function_index = compile_proc_function(program, stmt)
        if function_index < 0:
            return false
        if not emit_define_function(chunk, stmt.name, function_index):
            return false
        if want_result:
            emit_op(chunk, BC_OP_NIL)
        return true

    if stmt.type == ast.STMT_EXPRESSION:
        if not compile_expr(chunk, stmt.expression):
            return false
        if not want_result:
            emit_op(chunk, BC_OP_POP)
        return true

    if stmt.type == ast.STMT_BLOCK:
        if not compile_block(program, chunk, stmt, allow_return):
            return false
        if want_result:
            emit_op(chunk, BC_OP_NIL)
        return true

    if stmt.type == ast.STMT_IF:
        if not compile_expr(chunk, stmt.condition):
            return false
        let else_jump = emit_jump(chunk, BC_OP_JUMP_IF_FALSE)
        emit_op(chunk, BC_OP_POP)
        if not compile_stmt(program, chunk, stmt.then_branch, false, allow_return):
            return false
        let end_jump = emit_jump(chunk, BC_OP_JUMP)
        if not patch_jump(chunk, else_jump, current_offset(chunk)):
            return false
        emit_op(chunk, BC_OP_POP)
        if stmt.else_branch != nil:
            if not compile_stmt(program, chunk, stmt.else_branch, false, allow_return):
                return false
        if not patch_jump(chunk, end_jump, current_offset(chunk)):
            return false
        if want_result:
            emit_op(chunk, BC_OP_NIL)
        return true

    if stmt.type == ast.STMT_WHILE:
        let loop_start = current_offset(chunk)
        if not compile_expr(chunk, stmt.condition):
            return false
        let exit_jump = emit_jump(chunk, BC_OP_JUMP_IF_FALSE)
        emit_op(chunk, BC_OP_POP)
        if not compile_stmt(program, chunk, stmt.body, false, allow_return):
            return false
        emit_op(chunk, BC_OP_JUMP)
        emit_u16(chunk, loop_start)
        if not patch_jump(chunk, exit_jump, current_offset(chunk)):
            return false
        emit_op(chunk, BC_OP_POP)
        if want_result:
            emit_op(chunk, BC_OP_NIL)
        return true

    if stmt.type == ast.STMT_FOR:
        let loop_var = stmt.variable
        if not compile_expr(chunk, stmt.iterable):
            return false
        emit_op(chunk, BC_OP_PUSH_ENV)
        if not emit_constant(chunk, number_constant(0, "0")):
            return false

        let loop_start = current_offset(chunk)
        if not emit_dup(chunk, 0):
            return false
        if not emit_dup(chunk, 2):
            return false
        emit_op(chunk, BC_OP_ARRAY_LEN)
        emit_op(chunk, BC_OP_LESS)
        let exit_jump = emit_jump(chunk, BC_OP_JUMP_IF_FALSE)
        emit_op(chunk, BC_OP_POP)

        if not emit_dup(chunk, 1):
            return false
        if not emit_dup(chunk, 1):
            return false
        emit_op(chunk, BC_OP_GET_INDEX)
        emit_name_op(chunk, BC_OP_DEFINE_GLOBAL, loop_var)

        if not compile_stmt(program, chunk, stmt.body, false, allow_return):
            return false

        if not emit_constant(chunk, number_constant(1, "1")):
            return false
        emit_op(chunk, BC_OP_ADD)
        emit_op(chunk, BC_OP_JUMP)
        emit_u16(chunk, loop_start)

        if not patch_jump(chunk, exit_jump, current_offset(chunk)):
            return false
        emit_op(chunk, BC_OP_POP)
        emit_op(chunk, BC_OP_POP)
        emit_op(chunk, BC_OP_POP)
        emit_op(chunk, BC_OP_POP_ENV)
        if want_result:
            emit_op(chunk, BC_OP_NIL)
        return true

    if stmt.type == ast.STMT_RETURN:
        if stmt.value != nil:
            if not compile_expr(chunk, stmt.value):
                return false
        else:
            emit_op(chunk, BC_OP_NIL)
        emit_op(chunk, BC_OP_RETURN)
        return true

    return unsupported_stmt()

proc compile_to_program(stmts):
    last_error = ""
    let program = new_program()
    for stmt in stmts:
        let chunk = new_chunk()
        if not compile_stmt(program, chunk, stmt, true, false):
            return nil
        emit_op(chunk, BC_OP_RETURN)
        push(program["chunks"], chunk)
    return program

proc hex_encode_bytes(values):
    let out = ""
    for i in range(len(values)):
        let value = values[i]
        out = out + HEX_DIGITS[(value >> 4) & 15]
        out = out + HEX_DIGITS[value & 15]
    return out

proc string_to_bytes(text):
    let values = []
    for i in range(len(text)):
        push(values, ord(text[i]))
    return values

proc format_int_constant(value):
    if value == 0:
        return "0"

    let sign = ""
    let current = value
    if current < 0:
        sign = "-"
        current = -current

    let digits = []
    while current > 0:
        push(digits, HEX_DIGITS[current % 10])
        current = stdlib.math_floor(current / 10)

    let out = sign
    let i = len(digits) - 1
    while i >= 0:
        out = out + digits[i]
        i = i - 1
    return out

proc format_number_constant(value):
    if value == stdlib.math_floor(value):
        return format_int_constant(value)
    return str(value)

proc chunk_payload_to_artifact_text(chunk, end_marker):
    let out = ""
    out = out + "constants " + str(len(chunk["constants"])) + NL
    for i in range(len(chunk["constants"])):
        let value = chunk["constants"][i]
        if type(value) == "dict" and dict_has(value, "kind") and value["kind"] == "number":
            out = out + "number " + value["text"] + NL
        else:
            if type(value) == "number":
                out = out + "number " + format_number_constant(value) + NL
            else:
                let bytes = string_to_bytes(value)
                out = out + "string " + str(len(value)) + NL
                out = out + hex_encode_bytes(bytes) + NL
    out = out + "code " + str(len(chunk["code"])) + NL
    out = out + hex_encode_bytes(chunk["code"]) + NL
    out = out + end_marker + NL
    return out

proc function_to_artifact_text(function):
    let out = "function" + NL
    out = out + "params " + str(len(function["params"])) + NL
    for i in range(len(function["params"])):
        let param = function["params"][i]
        let bytes = string_to_bytes(param)
        out = out + "param " + str(len(param)) + NL
        out = out + hex_encode_bytes(bytes) + NL
    out = out + chunk_payload_to_artifact_text(function["chunk"], "endfunction")
    return out

proc chunk_to_artifact_text(chunk):
    return "chunk" + NL + chunk_payload_to_artifact_text(chunk, "endchunk")

proc compile_to_vm_artifact(stmts):
    let program = compile_to_program(stmts)
    if program == nil:
        return nil

    let out = "SAGEBC1" + NL
    out = out + "functions " + str(len(program["functions"])) + NL
    for i in range(len(program["functions"])):
        out = out + function_to_artifact_text(program["functions"][i])
    out = out + "chunks " + str(len(program["chunks"])) + NL
    for i in range(len(program["chunks"])):
        out = out + chunk_to_artifact_text(program["chunks"][i])
    return out
