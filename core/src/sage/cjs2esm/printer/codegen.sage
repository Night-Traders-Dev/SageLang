# -----------------------------------------
# printer/codegen.sage - ESM Source Code Generator
# Formats transformed AST back to JavaScript source code
# -----------------------------------------

import AST
from AST import (
    Program, ImportDeclaration, ImportSpecifier, ImportDefaultSpecifier,
    ExportNamedDeclaration, ExportDefaultDeclaration, ExportSpecifier,
    Literal, Identifier, CallExpression, MemberExpression,
    BlockStatement, IfStatement, ForStatement, ReturnStatement,
    ExpressionStatement, VariableDeclaration, VariableDeclarator,
    TryStatement, CatchClause, ThrowStatement
)

# --- Generate indentation based on nesting level ---
proc indent_text(text, level = 0):
    """Add indentation to multi-line text."""
    if text == nil or text == "":
        return text
    
    spaces = "  " * level  # 2-space indentation
    lines = text.split(chr(10))
    indented_lines = []
    for line in lines:
        if line.strip():  # non-empty line
            indented_lines.append(spaces + line)
        else:
            indented_lines.append("")  # preserve blank lines
    return chr(10).join(indented_lines)

# --- Print ImportDeclaration ---
proc print_import_declaration(imp, depth = 0):
    """Print an ESM import declaration."""
    spaces = "  " * depth
    
    if imp.import_attributes and "json" in str(imp.import_attributes):
        # import ... with { type: "json" }
        return f'{spaces}import {imp.source} with {{ type: "json" }};'
    
    # Named imports: import { spec1, spec2 } from "module"
    if imp.specifiers:
        imported_names = ", ".join([s.local for s in imp.specifiers])
        return f'{spaces}import {{ {imported_names} }} from "{imp.source}";'
    
    # Default import only: import ... from "module"
    return f'{spaces}import {{ }} from "{imp.source}";'

# --- Print ExportNamedDeclaration ---
proc print_export_named_declaration(exp, depth = 0):
    """Print an ESM named export declaration."""
    spaces = "  " * depth
    
    if exp.is_default and exp.source == nil:
        # export default expression/object
        if exp.expression:
            expr_str = print_expression(exp.expression, depth)
            return f'{spaces}export default {expr_str};'
        return f'{spaces}export default ;'
    
    if exp.exported_specifiers:
        exported_names = ", ".join([f"{s.exported}" for s in exp.exported_specifiers])
        return f'{spaces}export {{ {exported_names} }} from "{exp.source}";'
    
    if exp.is_default and exp.source:
        # export default from "module"
        return f'{spaces}export default from "{exp.source}";'
    
    return ""

# --- Print ExportDefaultDeclaration ---
proc print_export_default_declaration(exp, depth = 0):
    """Print an ESM default export declaration."""
    spaces = "  " * depth
    
    if exp.expression:
        expr_str = print_expression(exp.expression, depth)
        return f'{spaces}export default {expr_str};'
    return f'{spaces}export default ;'

# --- Print Literal ---
proc print_literal(lit, depth = 0):
    """Print a literal value."""
    if lit.kind == "string":
        return f'"{lit.value}"'
    elif lit.kind == "number":
        return str(lit.value)
    elif lit.kind == "bool":
        return "true" if lit.value else "false"
    elif lit.kind == "nil":
        return "null"
    return str(lit.value)

# --- Print Identifier ---
proc print_identifier(ident, depth = 0):
    """Print an identifier name."""
    return ident.name

# --- Print MemberExpression (e.g., module.exports, require.cache) ---
proc print_member_expression(member, depth = 0):
    """Print a member expression like module.exports or obj.prop."""
    spaces = "  " * depth
    
    obj_str = print_identifier(member.object, depth) if member.object else ""
    prop_str = print_identifier(member.property, depth) if member.property else ""
    
    if member.computed:
        return f'{spaces}({obj_str}[{prop_str}])'
    else:
        if obj_str:
            return f'{spaces}{obj_str}.{prop_str}'
        return prop_str

# --- Print CallExpression (e.g., require(), module.exports = ...) ---
proc print_call_expression(call, depth = 0):
    """Print a function call expression."""
    spaces = "  " * depth
    
    callee_str = ""
    if call.callee:
        if member_expr := call.callee:  # Check if it's a MemberExpression
            callee_str = print_member_expression(member_expr, depth)
        else:
            callee_str = print_identifier(call.callee, depth)
    
    args_str = ""
    if call.args:
        arg_parts = []
        for arg in call.args:
            arg_parts.append(print_expression(arg, depth))
        args_str = ", ".join(arg_parts)
    
    return f'{spaces}{callee_str}({args_str})'

# --- Print MemberExpression for require/cache ---
proc print_require_call(depth = 0):
    """Print require() call with createRequire shim context."""
    spaces = "  " * depth
    return f'{spaces}require({{" module: ".." }}"})'  # placeholder

# --- Print BlockStatement ---
proc print_block_statement(block, depth = 0):
    """Print a block of statements."""
    spaces = "  " * depth
    lines = []
    for stmt in block.statements:
        stmt_str = print_statement(stmt, depth + 1)
        if stmt_str:
            lines.append(stmt_str)
    if lines:
        return "{\n" + chr(10).join(lines) + "\n" + spaces + "}"
    return "{}"

# --- Print IfStatement ---
proc print_if_statement(stmt, depth = 0):
    """Print an if/else statement."""
    spaces = "  " * depth
    cond = print_expression(stmt.condition, depth)
    then_branch = print_block_statement(stmt.then_branch, depth + 1)
    
    result = f'{spaces}if ({cond}) {{\n{then_branch}\n{spaces}}}'
    
    if stmt.else_branch:
        if isinstance(stmt.else_branch, IfStatement):
            result += "\n" + print_if_statement(stmt.else_branch, depth)
        else:
            else_branch = print_block_statement(stmt.else_branch, depth + 1)
            result += f'\n{spaces}else {{\n{else_branch}\n{spaces}}}'
    
    return result

# --- Print VariableDeclaration ---
proc print_variable_declaration(decl, depth = 0):
    """Print a var/let/const declaration."""
    spaces = "  " * depth
    kind = decl.kind  # "var", "let", "const"
    
    parts = []
    for var_decl in decl.declarations:
        init_str = ""
        if var_decl.init:
            init_str = " = " + print_expression(var_decl.init, depth)
        parts.append(f'{spaces}{kind} {var_decl.id.name}{init_str}')
    
    if parts:
        return chr(10).join(parts)
    return ""

# --- Print ExpressionStatement ---
proc print_expression_statement(stmt, depth = 0):
    """Print an expression statement."""
    spaces = "  " * depth
    return spaces + print_expression(stmt.expression, depth) + ";"

# --- Print Expression (dispatcher) ---
proc print_expression(expr, depth = 0):
    """Dispatch to the correct printer based on expression type."""
    if expr == nil:
        return "nil"
    
    t = expr.type
    
    if t == AST.EXPR_NUMBER:
        return print_literal(expr)
    
    if t == AST.EXPR_STRING:
        return print_literal(expr)
    
    if t == AST.EXPR_BOOL:
        return print_literal(expr)
    
    if t == AST.EXPR_VARIABLE:
        return print_identifier(expr)
    
    if t == AST.EXPR_CALL:
        return print_call_expression(expr, depth)
    
    if t == AST.EXPR_MEMBER:
        return print_member_expression(expr, depth)
    
    if t == AST.EXPR_GET:
        obj_str = print_expression(expr.object, depth)
        prop_str = print_identifier(expr.property, depth)
        return f'{obj_str}.{prop_str}'
    
    if t == AST.EXPR_SET:
        obj_str = print_expression(expr.object, depth)
        prop_str = print_identifier(expr.property, depth)
        val_str = print_expression(expr.value, depth)
        return f'{obj_str}.{prop_str} = {val_str}'
    
    if t == AST.EXPR_CONDITIONAL:
        test_str = print_expression(expr.test, depth)
        cons_str = print_expression(expr.consequent, depth)
        alt_str = print_expression(expr.alternate, depth)
        return f'({test_str} ? {cons_str} : {alt_str})'
    
    if t == AST.EXPR_UNARY:
        op = expr.op if hasattr(expr, 'op') else ""
        arg_str = print_expression(expr.arg, depth + 1)
        return f'{op}{arg_str}'
    
    # Fallback: print by name
    return str(expr) if expr else ""

# --- Print Program ---
proc print_program(program, depth = 0):
    """Print the entire program (ESM module)."""
    spaces = "  " * depth
    lines = []
    
    # Print import declarations first (they're hoisted in ESM)
    for stmt in program.body:
        if isinstance(stmt, ImportDeclaration):
            imp_str = print_import_declaration(stmt, depth)
            if imp_str:
                lines.append(imp_str)
    
    # Print export declarations
    for stmt in program.body:
        if isinstance(stmt, (ExportNamedDeclaration, ExportDefaultDeclaration)):
            if isinstance(stmt, ExportNamedDeclaration):
                exp_str = print_export_named_declaration(stmt, depth)
            else:
                exp_str = print_export_default_declaration(stmt, depth)
            if exp_str:
                lines.append(exp_str)
    
    # Print remaining statements (keeping original order for compat mode)
    for stmt in program.body:
        if not isinstance(stmt, (ImportDeclaration, ExportNamedDeclaration, ExportDefaultDeclaration)):
            stmt_str = print_statement(stmt, depth)
            if stmt_str:
                lines.append(stmt_str)
    
    return chr(10).join(lines)