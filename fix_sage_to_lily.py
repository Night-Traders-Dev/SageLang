with open("core/lib/transpiler/lily/sage_to_lily.sage", "r") as f:
    text = f.read()

import re

# Fix "if stmt == nil\nlet type = stmt.type"
text = text.replace("if stmt == nil\n        let type = stmt.type", "if stmt == nil:\n            return\n        let type = stmt.type")

# Fix ".write_indent()" and other weird trailing method calls that replaced ":"
text = re.sub(r'(if|elif)(.*?)(ast\.STMT_[A-Z_]+)\.write_indent\(\)', r'\1\2\3:\n            self.write_indent()', text)
text = re.sub(r'if (.*?)\.write\("(.*?)"\)', r'if \1:\n            self.write("\2")', text)

with open("core/lib/transpiler/lily/sage_to_lily.sage", "w") as f:
    f.write(text)
