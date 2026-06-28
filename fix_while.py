with open("core/lib/transpiler/lily/sage_to_lily.sage", "r") as f:
    text = f.read()

text = text.replace("while curr != nil.emit_stmt(curr)", "while curr != nil:\n                self.emit_stmt(curr.value)")

with open("core/lib/transpiler/lily/sage_to_lily.sage", "w") as f:
    f.write(text)
