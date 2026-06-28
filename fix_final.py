import re
with open("core/lib/transpiler/lily/sage_to_lily.sage", "r") as f:
    lines = f.readlines()

out = []
for i, line in enumerate(lines):
    s = line.strip()
    if s.startswith("self.emit_expr") or s.startswith("self.emit_stmt") or s.startswith("self.write") or s.startswith("is_ptr") or s.startswith("is_addr") or s.startswith("let ") or s.startswith("curr =") or s.startswith("if ") or s.startswith("while ") or s.startswith("for ") or s.startswith("elif ") or s.startswith("else:") or s.startswith("return"):
        # Fix indentation
        # Generally, if the previous line ends with ':', this line should be indented 4 spaces more than the previous line
        pass
    
    # Just fix the ridiculous >20 space indents
    if len(line) - len(line.lstrip()) > 20:
        # It's probably 12 or 16 spaces
        if "if " in lines[i-1] or "while " in lines[i-1] or "for " in lines[i-1] or "elif " in lines[i-1] or "else:" in lines[i-1]:
            prev_indent = len(lines[i-1]) - len(lines[i-1].lstrip())
            line = " " * (prev_indent + 4) + s + "\n"
        else:
            prev_indent = len(lines[i-1]) - len(lines[i-1].lstrip())
            line = " " * prev_indent + s + "\n"
            
    out.append(line)

with open("core/lib/transpiler/lily/sage_to_lily.sage", "w") as f:
    f.writelines(out)
