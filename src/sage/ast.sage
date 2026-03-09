gc_disable()
# -----------------------------------------
# ast.sage - AST node definitions for SageLang self-hosted compiler
# Expression and Statement node types with factory functions
# -----------------------------------------

# --- Expression type constants ---
let EXPR_NUMBER = 0
let EXPR_STRING = 1
let EXPR_BOOL = 2
let EXPR_NIL = 3
let EXPR_BINARY = 4
let EXPR_VARIABLE = 5
let EXPR_CALL = 6
let EXPR_ARRAY = 7
let EXPR_INDEX = 8
let EXPR_DICT = 9
let EXPR_TUPLE = 10
let EXPR_SLICE = 11
let EXPR_GET = 12
let EXPR_SET = 13
let EXPR_INDEX_SET = 14
let EXPR_AWAIT = 15

# --- Statement type constants ---
let STMT_PRINT = 100
let STMT_EXPRESSION = 101
let STMT_LET = 102
let STMT_IF = 103
let STMT_BLOCK = 104
let STMT_WHILE = 105
let STMT_PROC = 106
let STMT_FOR = 107
let STMT_RETURN = 108
let STMT_BREAK = 109
let STMT_CONTINUE = 110
let STMT_CLASS = 111
let STMT_MATCH = 112
let STMT_DEFER = 113
let STMT_TRY = 114
let STMT_RAISE = 115
let STMT_YIELD = 116
let STMT_IMPORT = 117
let STMT_ASYNC_PROC = 118

# --- Expression node class ---
class Expr:
    proc init(expr_type):
        self.type = expr_type

# --- Statement node class ---
class Stmt:
    proc init(stmt_type):
        self.type = stmt_type
        self.next = nil

# --- Expression type name (for debugging) ---
proc expr_type_name(t):
    if t == EXPR_NUMBER:
        return "EXPR_NUMBER"
    if t == EXPR_STRING:
        return "EXPR_STRING"
    if t == EXPR_BOOL:
        return "EXPR_BOOL"
    if t == EXPR_NIL:
        return "EXPR_NIL"
    if t == EXPR_BINARY:
        return "EXPR_BINARY"
    if t == EXPR_VARIABLE:
        return "EXPR_VARIABLE"
    if t == EXPR_CALL:
        return "EXPR_CALL"
    if t == EXPR_ARRAY:
        return "EXPR_ARRAY"
    if t == EXPR_INDEX:
        return "EXPR_INDEX"
    if t == EXPR_DICT:
        return "EXPR_DICT"
    if t == EXPR_TUPLE:
        return "EXPR_TUPLE"
    if t == EXPR_SLICE:
        return "EXPR_SLICE"
    if t == EXPR_GET:
        return "EXPR_GET"
    if t == EXPR_SET:
        return "EXPR_SET"
    if t == EXPR_INDEX_SET:
        return "EXPR_INDEX_SET"
    if t == EXPR_AWAIT:
        return "EXPR_AWAIT"
    return "UNKNOWN_EXPR"

# --- Statement type name (for debugging) ---
proc stmt_type_name(t):
    if t == STMT_PRINT:
        return "STMT_PRINT"
    if t == STMT_EXPRESSION:
        return "STMT_EXPRESSION"
    if t == STMT_LET:
        return "STMT_LET"
    if t == STMT_IF:
        return "STMT_IF"
    if t == STMT_BLOCK:
        return "STMT_BLOCK"
    if t == STMT_WHILE:
        return "STMT_WHILE"
    if t == STMT_PROC:
        return "STMT_PROC"
    if t == STMT_FOR:
        return "STMT_FOR"
    if t == STMT_RETURN:
        return "STMT_RETURN"
    if t == STMT_BREAK:
        return "STMT_BREAK"
    if t == STMT_CONTINUE:
        return "STMT_CONTINUE"
    if t == STMT_CLASS:
        return "STMT_CLASS"
    if t == STMT_MATCH:
        return "STMT_MATCH"
    if t == STMT_DEFER:
        return "STMT_DEFER"
    if t == STMT_TRY:
        return "STMT_TRY"
    if t == STMT_RAISE:
        return "STMT_RAISE"
    if t == STMT_YIELD:
        return "STMT_YIELD"
    if t == STMT_IMPORT:
        return "STMT_IMPORT"
    if t == STMT_ASYNC_PROC:
        return "STMT_ASYNC_PROC"
    return "UNKNOWN_STMT"

# -----------------------------------------
# Expression factory functions
# -----------------------------------------

proc number_expr(value):
    let e = Expr(EXPR_NUMBER)
    e.value = value
    return e

proc string_expr(value):
    let e = Expr(EXPR_STRING)
    e.value = value
    return e

proc bool_expr(value):
    let e = Expr(EXPR_BOOL)
    e.value = value
    return e

proc nil_expr():
    let e = Expr(EXPR_NIL)
    return e

proc binary_expr(left, op, right):
    let e = Expr(EXPR_BINARY)
    e.left = left
    e.op = op
    e.right = right
    return e

proc variable_expr(name):
    let e = Expr(EXPR_VARIABLE)
    e.name = name
    return e

proc call_expr(callee, args):
    let e = Expr(EXPR_CALL)
    e.callee = callee
    e.args = args
    e.arg_count = len(args)
    return e

proc array_expr(elements):
    let e = Expr(EXPR_ARRAY)
    e.elements = elements
    e.count = len(elements)
    return e

proc index_expr(obj, idx):
    let e = Expr(EXPR_INDEX)
    e.object = obj
    e.index = idx
    return e

proc index_set_expr(obj, idx, value):
    let e = Expr(EXPR_INDEX_SET)
    e.object = obj
    e.index = idx
    e.value = value
    return e

proc dict_expr(keys, values):
    let e = Expr(EXPR_DICT)
    e.keys = keys
    e.values = values
    e.count = len(keys)
    return e

proc tuple_expr(elements):
    let e = Expr(EXPR_TUPLE)
    e.elements = elements
    e.count = len(elements)
    return e

proc slice_expr(obj, start_expr, end_expr):
    let e = Expr(EXPR_SLICE)
    e.object = obj
    e.start = start_expr
    e.end = end_expr
    return e

proc get_expr(obj, prop):
    let e = Expr(EXPR_GET)
    e.object = obj
    e.property = prop
    return e

proc set_expr(obj, prop, value):
    let e = Expr(EXPR_SET)
    e.object = obj
    e.property = prop
    e.value = value
    return e

proc await_expr(expression):
    let e = Expr(EXPR_AWAIT)
    e.expression = expression
    return e

# -----------------------------------------
# Statement factory functions
# -----------------------------------------

proc print_stmt(expression):
    let s = Stmt(STMT_PRINT)
    s.expression = expression
    return s

proc expr_stmt(expression):
    let s = Stmt(STMT_EXPRESSION)
    s.expression = expression
    return s

proc let_stmt(name, initializer):
    let s = Stmt(STMT_LET)
    s.name = name
    s.initializer = initializer
    return s

proc if_stmt(condition, then_branch, else_branch):
    let s = Stmt(STMT_IF)
    s.condition = condition
    s.then_branch = then_branch
    s.else_branch = else_branch
    return s

proc block_stmt(statements):
    let s = Stmt(STMT_BLOCK)
    s.statements = statements
    return s

proc while_stmt(condition, body):
    let s = Stmt(STMT_WHILE)
    s.condition = condition
    s.body = body
    return s

proc proc_stmt(name, params, body):
    let s = Stmt(STMT_PROC)
    s.name = name
    s.params = params
    s.param_count = len(params)
    s.body = body
    return s

proc for_stmt(variable, iterable, body):
    let s = Stmt(STMT_FOR)
    s.variable = variable
    s.iterable = iterable
    s.body = body
    return s

proc return_stmt(value):
    let s = Stmt(STMT_RETURN)
    s.value = value
    return s

proc break_stmt():
    let s = Stmt(STMT_BREAK)
    return s

proc continue_stmt():
    let s = Stmt(STMT_CONTINUE)
    return s

proc class_stmt(name, parent, has_parent, methods):
    let s = Stmt(STMT_CLASS)
    s.name = name
    s.parent = parent
    s.has_parent = has_parent
    s.methods = methods
    return s

proc try_stmt(try_block, catches, finally_block):
    let s = Stmt(STMT_TRY)
    s.try_block = try_block
    s.catches = catches
    s.catch_count = len(catches)
    s.finally_block = finally_block
    return s

proc raise_stmt(exception):
    let s = Stmt(STMT_RAISE)
    s.exception = exception
    return s

proc yield_stmt(value):
    let s = Stmt(STMT_YIELD)
    s.value = value
    return s

proc import_stmt(module_name, items, item_aliases, alias, import_all):
    let s = Stmt(STMT_IMPORT)
    s.module_name = module_name
    s.items = items
    s.item_aliases = item_aliases
    s.item_count = len(items)
    s.alias = alias
    s.import_all = import_all
    return s

proc async_proc_stmt(name, params, body):
    let s = Stmt(STMT_ASYNC_PROC)
    s.name = name
    s.params = params
    s.param_count = len(params)
    s.body = body
    return s

proc defer_stmt(statement):
    let s = Stmt(STMT_DEFER)
    s.statement = statement
    return s

# --- CatchClause helper ---
class CatchClause:
    proc init(exception_var, body):
        self.exception_var = exception_var
        self.body = body
