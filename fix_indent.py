with open("core/lib/transpiler/lily/sage_to_lily.sage", "r") as f:
    lines = f.readlines()

out = []
for i, line in enumerate(lines):
    if line.strip() == 'self.write(" = ")' and lines[i-1].strip() == 'if stmt.initializer != nil:':
        out.append("                self.write(\" = \")\n")
    else:
        out.append(line)

with open("core/lib/transpiler/lily/sage_to_lily.sage", "w") as f:
    f.writelines(out)
