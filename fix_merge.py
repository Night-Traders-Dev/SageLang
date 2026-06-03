with open("core/lib/arrays.sage", "r") as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if line.startswith("<<<<<<< HEAD"):
        skip = True
        continue
    if line.startswith("======="):
        skip = False
        continue
    if line.startswith(">>>>>>>"):
        continue
    if not skip:
        new_lines.append(line)

with open("core/lib/arrays.sage", "w") as f:
    f.writelines(new_lines)
