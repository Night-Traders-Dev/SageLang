with open("core/lib/transpiler/lily/sage_to_lily.sage", "r") as f:
    lines = f.readlines()

out = []
for i, line in enumerate(lines):
    if "self.write(" in line and lines[i-1].strip().startswith("if "):
        if line.startswith("            self.write"): pass
        else: line = "    " + line
    out.append(line)

with open("core/lib/transpiler/lily/sage_to_lily.sage", "w") as f:
    f.writelines(out)
