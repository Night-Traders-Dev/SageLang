with open("core/src/c/interpreter.c", "r") as f:
    text = f.read()

text = text.replace('fprintf(stderr, "\\n");', 'fprintf(stderr, "\\n"); fflush(stdout);')

with open("core/src/c/interpreter.c", "w") as f:
    f.write(text)
