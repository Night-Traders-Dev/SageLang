with open("core/lib/transpiler/lily/sage_to_lily.sage", "r") as f:
    lines = f.readlines()

out = []
for i, line in enumerate(lines):
    if line.strip() in ['self.emit_expr(stmt.value)', 'self.emit_stmt(curr.value)', 'self.write_indent()', 'self.write(" as " + stmt.item_aliases[i])', 'self.write(" as " + stmt.alias)', 'self.write(": " + stmt.field_types[i].text)', 'self.emit_expr(expr.start)', 'self.emit_expr(expr.end)'] and lines[i-1].strip().startswith("if "):
        indent = len(lines[i-1]) - len(lines[i-1].lstrip())
        out.append(" " * (indent + 4) + line.lstrip())
    else:
        out.append(line)

with open("core/lib/transpiler/lily/sage_to_lily.sage", "w") as f:
    f.writelines(out)
