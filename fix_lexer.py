import re
lines = open("core/lib/transpiler/lily/lily_lexer.sage").readlines()
out = []
for line in lines:
    m = re.match(r'^(\s*)(if|elif|else)(.*):\s+(.*)$', line)
    if m:
        indent = m.group(1)
        out.append(f"{indent}{m.group(2)}{m.group(3)}:\n{indent}    {m.group(4)}\n")
    else:
        out.append(line)
open("core/lib/transpiler/lily/lily_lexer.sage", "w").write("".join(out))
