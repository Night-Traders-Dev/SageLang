import re

for filename in ["core/lib/transpiler/lily/lily_lexer.sage", "core/lib/transpiler/lily/lily_parser.sage"]:
    with open(filename, "r") as f:
        text = f.read()
    
    text = re.sub(r'if (.*?) nil\n', r'if \1: return nil\n', text)
    text = re.sub(r'if (.*?) false\n', r'if \1: return false\n', text)
    text = re.sub(r'if (.*?) true\n', r'if \1: return true\n', text)
    
    with open(filename, "w") as f:
        f.write(text)
