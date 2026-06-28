with open("core/src/c/interpreter.c", "r") as f:
    text = f.read()

text = text.replace('fprintf(stderr, "Runtime Error: Invalid indexing operation.\\n");', 
                    'fprintf(stderr, "Runtime Error: Invalid indexing operation.\\n");\n                fprintf(stderr, "arr: "); print_value(arr); fprintf(stderr, "\\nidx: "); print_value(idx); fprintf(stderr, "\\n");')
text = text.replace('fprintf(stderr, "Runtime Error: Only instances and modules have properties.\\n");',
                    'fprintf(stderr, "Runtime Error: Only instances and modules have properties.\\n");\n            fprintf(stderr, "object: "); print_value(object); fprintf(stderr, "\\n");')

text = text.replace('fprintf(stderr, "Runtime Error: Invalid index assignment. arr.type=%d, idx.type=%d\\n", arr.type, idx.type);',
                    'fprintf(stderr, "Runtime Error: Invalid index assignment. arr.type=%d, idx.type=%d\\n", arr.type, idx.type);\n                fprintf(stderr, "arr: "); print_value(arr); fprintf(stderr, "\\nidx: "); print_value(idx); fprintf(stderr, "\\n");')

with open("core/src/c/interpreter.c", "w") as f:
    f.write(text)
