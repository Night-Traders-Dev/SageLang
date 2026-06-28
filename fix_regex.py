import re

for filename in ["core/lib/transpiler/lily/lily_lexer.sage", "core/lib/transpiler/lily/lily_parser.sage"]:
    with open(filename, "r") as f:
        text = f.read()
    
    # Fix `else.something` -> `else:\n    self.something`
    text = re.sub(r'else\.(.*?)\n', r'else:\n                self.\1\n', text)
    
    # Fix `if cond.something` -> `if cond:\n    self.something`
    # But ONLY if it's missing a colon!
    text = re.sub(r'if (.*? != nil|.*? == nil|.*? == .*?|.*? > .*?|.*? < .*?)\.(.*?)\n', r'if \1:\n                self.\2\n', text)
    
    with open(filename, "w") as f:
        f.write(text)
