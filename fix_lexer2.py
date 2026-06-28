lines = open("core/lib/transpiler/lily/lily_lexer.sage").read().split('\n')
out = []
i = 0
while i < len(lines):
    line = lines[i]
    if line.strip() == "":
        i += 1
        continue
    # If the line ends with ':' and the next line is just a comment that got separated
    # well actually, let's just use `black` or `autopep8`? No, it's Sage code, not Python.
    out.append(line)
    i += 1

open("core/lib/transpiler/lily/lily_lexer.sage", "w").write("\n".join(out))
