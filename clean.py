with open("core/lib/transpiler/lily/sage_to_lily.sage", "r") as f:
    lines = [l.strip() for l in f.readlines()]

out = []
indent = 0
for line in lines:
    if not line:
        continue
    
    if line.startswith("proc ") or line.startswith("class ") or line.startswith("from transpiler") or line.startswith("import "):
        indent = 0
        if line.startswith("proc "):
            indent = 1
            if line.startswith("proc parse") or line.startswith("proc emit"):
                indent = 1
    
    if line.startswith("proc emit_stmt"): indent = 1
    if line.startswith("proc emit_expr"): indent = 1
    if line.startswith("proc write_indent"): indent = 1
    
    # Specific known statements
    if line.startswith("if type ==") or line.startswith("elif type ==") or line.startswith("if expr == nil"):
        indent = 2
        
    if line.startswith("else.write") or line.startswith("else.emit_expr"):
        indent = 2
        
    if line == "else:":
        indent -= 1
        
    out.append(" " * (indent * 4) + line + "\n")
    
    if line.endswith(":"):
        indent += 1

with open("core/lib/transpiler/lily/sage_to_lily.sage", "w") as f:
    f.writelines(out)
