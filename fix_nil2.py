with open("core/lib/transpiler/lily/lily_lexer.sage", "r") as f:
    text = f.read()

text = text.replace(": return: return ", ": return ")
text = text.replace(": return: return", ": return ")

with open("core/lib/transpiler/lily/lily_lexer.sage", "w") as f:
    f.write(text)
