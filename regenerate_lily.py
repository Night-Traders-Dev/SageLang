import os

content = """from transpiler.base import Transpiler
import transpiler.lily.lily_parser as lily_parser
import ast

class LilyToSageTranspiler(Transpiler):
    proc init(self):
        self.output = []
        self.indent_level = 0

    proc parse(self, source):
        return lily_parser.parse_lily_source(source)

    proc emit(self, ast_stmts):
        self.output = []
        self.indent_level = 0
        for stmt in ast_stmts:
            self.emit_stmt(stmt)
        return join(self.output, "")

    proc write(self, text):
        push(self.output, text)

    proc write_indent(self):
        for i in range(self.indent_level):
            self.write("    ")

    proc emit_stmt(self, stmt):
        if stmt == nil:
            return
        let type = stmt.type
        if type == ast.STMT_LET:
            self.write_indent()
            self.write("let ")
            self.write(stmt.name.text)
            if stmt.initializer != nil:
                self.write(" = ")
                self.emit_expr(stmt.initializer)
            self.write(chr(10))
        elif type == ast.STMT_PROC:
            self.write_indent()
            self.write("proc ")
            self.write(stmt.name.text)
            self.write("(")
            let count = len(stmt.params)
            for i in range(count):
                self.write(stmt.params[i].text)
                if i < count - 1:
                    self.write(", ")
            self.write("):\\n")
            self.emit_stmt(stmt.body)
        elif type == ast.STMT_EXPRESSION:
            self.write_indent()
            self.emit_expr(stmt.expression)
            self.write(chr(10))
        elif type == ast.STMT_RETURN:
            self.write_indent()
            self.write("return ")
            if stmt.value != nil:
                self.emit_expr(stmt.value)
            self.write(chr(10))
        elif type == ast.STMT_PRINT:
            self.write_indent()
            self.write("print(")
            self.emit_expr(stmt.expression)
            self.write(")\\n")
        elif type == ast.STMT_IF:
            self.write_indent()
            self.write("if ")
            self.emit_expr(stmt.condition)
            self.write(":\\n")
            self.emit_stmt(stmt.then_branch)
            if stmt.else_branch != nil:
                self.write_indent()
                self.write("else:\\n")
                self.emit_stmt(stmt.else_branch)
        elif type == ast.STMT_BLOCK:
            self.indent_level = self.indent_level + 1
            let curr = stmt.statements
            while curr != nil:
                self.emit_stmt(curr.value)
                curr = curr.next
            self.indent_level = self.indent_level - 1
        elif type == ast.STMT_WHILE:
            self.write_indent()
            self.write("while ")
            self.emit_expr(stmt.condition)
            self.write(":\\n")
            self.emit_stmt(stmt.body)
        elif type == ast.STMT_FOR:
            self.write_indent()
            self.write("for ")
            self.write(stmt.variable.text)
            self.write(" in ")
            self.emit_expr(stmt.iterable)
            self.write(":\\n")
            self.emit_stmt(stmt.body)
        elif type == ast.STMT_BREAK:
            self.write_indent()
            self.write("break\\n")
        elif type == ast.STMT_CONTINUE:
            self.write_indent()
            self.write("continue\\n")
        elif type == ast.STMT_CLASS:
            self.write_indent()
            self.write("class ")
            self.write(stmt.name.text)
            if stmt.has_parent:
                self.write(" extends ")
                self.write(stmt.parent.text)
            self.write(":\\n")
            self.indent_level = self.indent_level + 1
            let curr = stmt.methods
            while curr != nil:
                self.emit_stmt(curr.value)
                curr = curr.next
            self.indent_level = self.indent_level - 1
        elif type == ast.STMT_DEFER:
            self.write_indent()
            self.write("defer ")
            self.emit_stmt(stmt.statement)
        elif type == ast.STMT_TRY:
            self.write_indent()
            self.write("try:\\n")
            self.emit_stmt(stmt.try_block)
            for c in stmt.catches:
                self.write_indent()
                self.write("catch " + c.exception_var.text + ":\\n")
                self.emit_stmt(c.body)
            if stmt.finally_block != nil:
                self.write_indent()
                self.write("finally:\\n")
                self.emit_stmt(stmt.finally_block)
        elif type == ast.STMT_RAISE:
            self.write_indent()
            self.write("raise ")
            self.emit_expr(stmt.exception)
            self.write("\\n")
        elif type == ast.STMT_YIELD:
            self.write_indent()
            self.write("yield ")
            if stmt.value != nil:
                self.emit_expr(stmt.value)
            self.write("\\n")
        elif type == ast.STMT_IMPORT:
            self.write_indent()
            if stmt.import_all:
                self.write("from " + stmt.module_name + " import *\\n")
            elif stmt.item_count > 0:
                self.write("from " + stmt.module_name + " import ")
                for i in range(stmt.item_count):
                    self.write(stmt.items[i])
                    if stmt.item_aliases[i] != nil:
                        self.write(" as " + stmt.item_aliases[i])
                    if i < stmt.item_count - 1:
                        self.write(", ")
                self.write("\\n")
            else:
                self.write("import " + stmt.module_name)
                if stmt.alias != nil:
                    self.write(" as " + stmt.alias)
                self.write("\\n")
        elif type == ast.STMT_ASYNC_PROC:
            self.write_indent()
            self.write("async proc ")
            self.write(stmt.name.text)
            self.write("(")
            let count = stmt.param_count
            for i in range(count):
                self.write(stmt.params[i].text)
                if i < count - 1:
                    self.write(", ")
            self.write("):\\n")
            self.emit_stmt(stmt.body)
        elif type == ast.STMT_STRUCT:
            self.write_indent()
            self.write("struct ")
            self.write(stmt.name.text)
            self.write(":\\n")
            self.indent_level = self.indent_level + 1
            for i in range(stmt.field_count):
                self.write_indent()
                self.write("var " + stmt.field_names[i].text)
                if stmt.field_types[i] != nil:
                    self.write(": " + stmt.field_types[i].text)
                self.write("\\n")
            self.indent_level = self.indent_level - 1
        elif type == ast.STMT_ENUM:
            self.write_indent()
            self.write("enum ")
            self.write(stmt.name.text)
            self.write(":\\n")
            self.indent_level = self.indent_level + 1
            for i in range(stmt.variant_count):
                self.write_indent()
                self.write(stmt.variant_names[i].text + "\\n")
            self.indent_level = self.indent_level - 1
        elif type == ast.STMT_TRAIT:
            self.write_indent()
            self.write("trait ")
            self.write(stmt.name.text)
            self.write(":\\n")
            self.indent_level = self.indent_level + 1
            let curr = stmt.methods
            while curr != nil:
                self.emit_stmt(curr.value)
                curr = curr.next
            self.indent_level = self.indent_level - 1
        elif type == ast.STMT_MATCH:
            self.write_indent()
            self.write("match ")
            self.emit_expr(stmt.value)
            self.write(":\\n")
            self.indent_level = self.indent_level + 1
            for i in range(stmt.case_count):
                let c = stmt.cases[i]
                self.write_indent()
                self.write("case ")
                self.emit_expr(c.pattern)
                if c.guard != nil:
                    self.write(" if ")
                    self.emit_expr(c.guard)
                self.write(":\\n")
                self.emit_stmt(c.body)
            if stmt.default_case != nil:
                self.write_indent()
                self.write("default:\\n")
                self.emit_stmt(stmt.default_case)
            self.indent_level = self.indent_level - 1
        elif type == ast.STMT_COMPTIME:
            self.write_indent()
            self.write("comptime:\\n")
            self.emit_stmt(stmt.body)
        elif type == ast.STMT_MACRO_DEF:
            self.write_indent()
            self.write("macro ")
            self.write(stmt.name.text)
            self.write("(")
            let count = stmt.param_count
            for i in range(count):
                self.write(stmt.params[i].text)
                if i < count - 1:
                    self.write(", ")
            self.write("):\\n")
            self.emit_stmt(stmt.body)
        else:
            self.write_indent()
            self.write("// TODO stmt type " + str(type))
            self.write(chr(10))

    proc emit_expr(self, expr):
        if expr == nil:
            return
        let type = expr.type
        if type == ast.EXPR_NUMBER:
            self.write(str(expr.value))
        elif type == ast.EXPR_STRING:
            self.write(chr(34) + expr.value + chr(34))
        elif type == ast.EXPR_VARIABLE:
            self.write(expr.name.text)
        elif type == ast.EXPR_BINARY:
            self.emit_expr(expr.left)
            self.write(" " + expr.op.text + " ")
            self.emit_expr(expr.right)
        elif type == ast.EXPR_CALL:
            self.emit_expr(expr.callee)
            self.write("(")
            let count = len(expr.args)
            for i in range(count):
                self.emit_expr(expr.args[i])
                if i < count - 1:
                    self.write(", ")
            self.write(")")
        elif type == ast.EXPR_BOOL:
            if expr.value:
                self.write("true")
            else:
                self.write("false")
        elif type == ast.EXPR_NIL:
            self.write("nil")
        elif type == ast.EXPR_ARRAY:
            self.write("[")
            let count = len(expr.elements)
            for i in range(count):
                self.emit_expr(expr.elements[i])
                if i < count - 1:
                    self.write(", ")
            self.write("]")
        elif type == ast.EXPR_DICT:
            self.write("{")
            let count = len(expr.keys)
            if count == 0:
                self.write(":")
            for i in range(count):
                self.emit_expr(expr.keys[i])
                self.write(": ")
                self.emit_expr(expr.values[i])
                if i < count - 1:
                    self.write(", ")
            self.write("}")
        elif type == ast.EXPR_INDEX:
            self.emit_expr(expr.object)
            self.write("[")
            self.emit_expr(expr.index)
            self.write("]")
        elif type == ast.EXPR_INDEX_SET:
            self.emit_expr(expr.object)
            self.write("[")
            self.emit_expr(expr.index)
            self.write("] = ")
            self.emit_expr(expr.value)
        elif type == ast.EXPR_GET:
            self.emit_expr(expr.object)
            self.write(".")
            self.write(expr.property.text)
        elif type == ast.EXPR_SET:
            self.emit_expr(expr.object)
            self.write(".")
            self.write(expr.property.text)
            self.write(" = ")
            self.emit_expr(expr.value)
        elif type == ast.EXPR_TUPLE:
            self.write("(")
            let count = len(expr.elements)
            for i in range(count):
                self.emit_expr(expr.elements[i])
                if i < count - 1:
                    self.write(", ")
            if count == 1:
                self.write(",")
            self.write(")")
        elif type == ast.EXPR_SLICE:
            self.emit_expr(expr.object)
            self.write("[")
            if expr.start != nil:
                self.emit_expr(expr.start)
            self.write(":")
            if expr.end != nil:
                self.emit_expr(expr.end)
            self.write("]")
        elif type == ast.EXPR_AWAIT:
            self.write("await ")
            self.emit_expr(expr.expression)
        elif type == ast.EXPR_SUPER:
            self.write("super.")
            self.write(expr.method.text)
        elif type == ast.EXPR_COMPTIME:
            self.write("comptime(")
            self.emit_expr(expr.expression)
            self.write(")")
        else:
            self.write("/* unhandled expr type " + str(type) + " */")
"""

with open("core/lib/transpiler/lily/lily_to_sage.sage", "w") as f:
    f.write(content)

