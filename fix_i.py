with open("core/lib/transpiler/lily/sage_to_lily.sage", "r") as f:
    lines = f.readlines()

out = []
for i, line in enumerate(lines):
    if line.strip() == 'self.write(", ")' and lines[i-1].strip() == 'if i < count - 1:':
        # Add 4 spaces to the indentation of the previous line
        indent = len(lines[i-1]) - len(lines[i-1].lstrip())
        out.append(" " * (indent + 4) + 'self.write(", ")\n')
    else:
        out.append(line)

with open("core/lib/transpiler/lily/sage_to_lily.sage", "w") as f:
    f.writelines(out)
