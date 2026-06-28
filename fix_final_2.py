with open("core/lib/transpiler/lily/sage_to_lily.sage", "r") as f:
    lines = f.readlines()

out = []
for line in lines:
    s = line.strip()
    if not s:
        out.append("\n")
        continue

    indent = 0
    if s.startswith("proc "):
        indent = 4
    elif s.startswith("if type == ast.STMT_") or s.startswith("if type == ast.EXPR_") or s.startswith("elif type == ast.STMT_") or s.startswith("elif type == ast.EXPR_") or s.startswith("if expr == nil:") or s.startswith("if stmt == nil:"):
        indent = 8
    elif s in ["self.write_indent()", "self.emit_stmt(stmt.body)"] or s.startswith("self.write(") or s.startswith("self.emit_expr(") or s.startswith("self.emit_stmt(") or s.startswith("let ") or s.startswith("for ") or s.startswith("if ") or s.startswith("elif ") or s.startswith("else:") or s.startswith("while ") or s.startswith("return") or s.startswith("curr =") or s.startswith("is_ptr =") or s.startswith("is_addr =") or s.startswith("push("):
        # We need to determine if it's inside a sub-block
        # We can just look at the last line's indent!
        pass
    
    # Actually, I will just write a custom formatter specifically for this file
    
    out.append(line)
