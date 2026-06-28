import re
lines = open("core/lib/transpiler/lily/lily_lexer.sage").read().split('\n')
out = []
i = 0
while i < len(lines):
    line = lines[i]
    if "self.make_token" in line and not line.strip().startswith("def") and not line.strip().startswith("proc"):
        # if the previous line is if, elif, else, check indentation
        prev_line = lines[i-1]
        m = re.match(r'^(\s*)(if|elif|else)', prev_line)
        if m:
            indent = m.group(1)
            # Make sure this line is indented 4 spaces more than the previous line
            if not line.startswith(indent + "    "):
                line = indent + "    " + line.strip()
    out.append(line)
    i += 1

open("core/lib/transpiler/lily/lily_lexer.sage", "w").write("\n".join(out))
