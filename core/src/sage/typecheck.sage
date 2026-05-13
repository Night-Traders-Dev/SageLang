gc_disable()
# SageLang Type Checker Pass (self-hosted port)
#
# Best-effort type inference for AST nodes.
# Tracks types of expressions and variables through a TypeMap.
# Currently informational only - does not transform the AST.
import ast

# Type kind constants
let TYPE_UNKNOWN = 0
let TYPE_NUMBER = 1
let TYPE_STRING = 2
let TYPE_BOOL = 3
let TYPE_NIL = 4
let TYPE_ARRAY = 5
let TYPE_DICT = 6
let TYPE_TUPLE = 7
let TYPE_FUNCTION = 8

# Type kind name for debugging
proc type_kind_name(kind):
    if kind == TYPE_UNKNOWN:
        return "unknown"
    if kind == TYPE_NUMBER:
        return "number"
    if kind == TYPE_STRING:
        return "string"
    if kind == TYPE_BOOL:
        return "bool"
    if kind == TYPE_NIL:
        return "nil"
    if kind == TYPE_ARRAY:
        return "array"
    if kind == TYPE_DICT:
        return "dict"
    if kind == TYPE_TUPLE:
        return "tuple"
    if kind == TYPE_FUNCTION:
        return "function"
    return "unknown"

# TypeMap: tracks inferred types for expressions and variable names
# Uses dicts for O(1) lookup
class TypeMap:
    proc init():
        # env maps variable name -> type kind
        self.env = {}

    proc set_var(name, kind):
        self.env[name] = kind

    proc get_var(name):
        if dict_has(self.env, name):
            return self.env[name]
        # TYPE_UNKNOWN = 0; hardcoded because class methods can't see module-level lets
        return 0

# Infer the type of an expression
proc infer_expr(tmap, expr):
    if expr == nil:
        return TYPE_UNKNOWN
    let t = expr.type
    if t == ast.EXPR_NUMBER:
        return TYPE_NUMBER
    if t == ast.EXPR_STRING:
        return TYPE_STRING
    if t == ast.EXPR_BOOL:
        return TYPE_BOOL
    if t == ast.EXPR_NIL:
        return TYPE_NIL
    if t == ast.EXPR_ARRAY:
        # Infer element types for potential future use
        for i in range(expr.count):
            infer_expr(tmap, expr.elements[i])
        return TYPE_ARRAY
    if t == ast.EXPR_DICT:
        for i in range(expr.count):
            infer_expr(tmap, expr.values[i])
        return TYPE_DICT
    if t == ast.EXPR_TUPLE:
        for i in range(expr.count):
            infer_expr(tmap, expr.elements[i])
        return TYPE_TUPLE
    if t == ast.EXPR_VARIABLE:
        return tmap.get_var(expr.name.text)
    if t == ast.EXPR_BINARY:
        let left_t = infer_expr(tmap, expr.left)
        let right_t = infer_expr(tmap, expr.right)
        let op = expr.op.text
        # Number + Number arithmetic
        if left_t == TYPE_NUMBER and right_t == TYPE_NUMBER:
            if op == "+" or op == "-" or op == "*" or op == "/" or op == "%":
                return TYPE_NUMBER
            # Comparison operators produce bool
            return TYPE_BOOL
        # String + String concatenation
        if left_t == TYPE_STRING and right_t == TYPE_STRING:
            if op == "+":
                return TYPE_STRING
            return TYPE_BOOL
        # Two-char operators (==, !=, <=, >=) produce bool
        if len(op) == 2:
            return TYPE_BOOL
        # Single-char < > produce bool
        if op == "<" or op == ">":
            return TYPE_BOOL
        return TYPE_UNKNOWN
    if t == ast.EXPR_CALL:
        infer_expr(tmap, expr.callee)
        for i in range(expr.arg_count):
            infer_expr(tmap, expr.args[i])
        return TYPE_UNKNOWN
    if t == ast.EXPR_INDEX:
        infer_expr(tmap, expr.object)
        infer_expr(tmap, expr.index)
        return TYPE_UNKNOWN
    if t == ast.EXPR_INDEX_SET:
        infer_expr(tmap, expr.object)
        infer_expr(tmap, expr.index)
        infer_expr(tmap, expr.value)
        return TYPE_UNKNOWN
    if t == ast.EXPR_SLICE:
        infer_expr(tmap, expr.object)
        infer_expr(tmap, expr.start)
        infer_expr(tmap, expr.end)
        return TYPE_UNKNOWN
    if t == ast.EXPR_GET:
        infer_expr(tmap, expr.object)
        return TYPE_UNKNOWN
    if t == ast.EXPR_SET:
        infer_expr(tmap, expr.object)
        infer_expr(tmap, expr.value)
        return TYPE_UNKNOWN
    return TYPE_UNKNOWN

# Infer types in a statement
proc infer_stmt(tmap, stmt):
    if stmt == nil:
        return
    let t = stmt.type
    if t == ast.STMT_PRINT:
        infer_expr(tmap, stmt.expression)
        return
    if t == ast.STMT_EXPRESSION:
        infer_expr(tmap, stmt.expression)
        return
    if t == ast.STMT_LET:
        let var_type = infer_expr(tmap, stmt.initializer)
        tmap.set_var(stmt.name.text, var_type)
        return
    if t == ast.STMT_IF:
        infer_expr(tmap, stmt.condition)
        infer_stmt_list(tmap, stmt.then_branch)
        infer_stmt_list(tmap, stmt.else_branch)
        return
    if t == ast.STMT_BLOCK:
        infer_stmt_list(tmap, stmt.statements)
        return
    if t == ast.STMT_WHILE:
        infer_expr(tmap, stmt.condition)
        infer_stmt_list(tmap, stmt.body)
        return
    if t == ast.STMT_PROC:
        # Register proc name as function type
        tmap.set_var(stmt.name.text, TYPE_FUNCTION)
        infer_stmt_list(tmap, stmt.body)
        return
    if t == ast.STMT_FOR:
        infer_expr(tmap, stmt.iterable)
        infer_stmt_list(tmap, stmt.body)
        return
    if t == ast.STMT_RETURN:
        infer_expr(tmap, stmt.value)
        return
    if t == ast.STMT_CLASS:
        infer_stmt_list(tmap, stmt.methods)
        return
    if t == ast.STMT_TRY:
        infer_stmt_list(tmap, stmt.try_block)
        for i in range(stmt.catch_count):
            infer_stmt_list(tmap, stmt.catches[i].body)
        infer_stmt_list(tmap, stmt.finally_block)
        return
    if t == ast.STMT_RAISE:
        infer_expr(tmap, stmt.exception)
        return
    if t == ast.STMT_YIELD:
        infer_expr(tmap, stmt.value)
        return
    if t == ast.STMT_DEFER:
        infer_stmt(tmap, stmt.statement)
        return

proc infer_stmt_list(tmap, head):
    let s = head
    while s != nil:
        infer_stmt(tmap, s)
        s = s.next

# Pass entry point
proc pass_typecheck(program, ctx):
    let tmap = TypeMap()
    infer_stmt_list(tmap, program)
    # Type checking is informational for now; does not transform AST
    return program
