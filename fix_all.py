import re

with open("core/lib/transpiler/lily/sage_to_lily.sage", "r") as f:
    text = f.read()

# Fix `if condition.method(...)` -> `if condition:\n    self.method(...)`
text = re.sub(r'if (.*?)\.write\((.*?)\)', r'if \1:\n            self.write(\2)', text)
text = re.sub(r'if (.*?)\.write_indent\(\)', r'if \1:\n            self.write_indent()', text)
text = re.sub(r'if (.*?)\.emit_expr\((.*?)\)', r'if \1:\n            self.emit_expr(\2)', text)

# Fix `elif type == ast.TYPE.method(...)`
text = re.sub(r'elif type == (ast\.[A-Z_]+)\.write\((.*?)\)', r'elif type == \1:\n            self.write(\2)', text)
text = re.sub(r'elif type == (ast\.[A-Z_]+)\.write_indent\(\)', r'elif type == \1:\n            self.write_indent()', text)
text = re.sub(r'elif type == (ast\.[A-Z_]+)\.emit_expr\((.*?)\)', r'elif type == \1:\n            self.emit_expr(\2)', text)
text = re.sub(r'elif type == (ast\.[A-Z_]+)\.indent_level = (.*?)\n', r'elif type == \1:\n            self.indent_level = \2\n', text)

# Fix `if type == ast.TYPE.method(...)`
text = re.sub(r'if type == (ast\.[A-Z_]+)\.write\((.*?)\)', r'if type == \1:\n            self.write(\2)', text)
text = re.sub(r'if type == (ast\.[A-Z_]+)\.write_indent\(\)', r'if type == \1:\n            self.write_indent()', text)
text = re.sub(r'if type == (ast\.[A-Z_]+)\.emit_expr\((.*?)\)', r'if type == \1:\n            self.emit_expr(\2)', text)

# Fix `if expr == nil`
text = re.sub(r'if expr == nil\n', r'if expr == nil:\n            return\n', text)

# Fix `elif type == ast.EXPR_BOOL expr.value:` -> `elif type == ast.EXPR_BOOL:\n    if expr.value:`
text = text.replace("elif type == ast.EXPR_BOOL expr.value:", "elif type == ast.EXPR_BOOL:\n            if expr.value:\n                self.write(\"true\")\n            else:\n                self.write(\"false\")")

# Fix EXPR_CALL is_ptr
text = re.sub(r'elif type == ast\.EXPR_CALL is_ptr = false\n', r'elif type == ast.EXPR_CALL:\n            let is_ptr = false\n            let is_addr = false\n', text)
text = re.sub(r'if expr\.callee\.type == ast\.EXPR_VARIABLE expr\.callee\.name\.text == "__deref__":', r'if expr.callee.type == ast.EXPR_VARIABLE and expr.callee.name.text == "__deref__":', text)

with open("core/lib/transpiler/lily/sage_to_lily.sage", "w") as f:
    f.write(text)

