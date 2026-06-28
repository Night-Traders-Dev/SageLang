with open("core/lib/transpiler/lily/sage_to_lily.sage", "r") as f:
    lines = [l.strip("\n").lstrip() for l in f.readlines()]

out = []
indent = 0
for i, line in enumerate(lines):
    if not line:
        out.append("\n")
        continue
    
    # dedent
    if line.startswith("elif ") or line.startswith("else:") or line.startswith("catch ") or line.startswith("finally:"):
        indent -= 1
        
    out.append(" " * (indent * 4) + line + "\n")
    
    # indent
    if line.endswith(":") or line.startswith("proc ") or line.startswith("class ") or line.startswith("struct "):
        indent += 1

with open("core/lib/transpiler/lily/sage_to_lily.sage", "w") as f:
    f.writelines(out)
