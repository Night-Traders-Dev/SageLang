with open("core/src/sage/interpreter.sage", "r") as f:
    text = f.read()

text = text.replace('let g_module_paths = [".", "lib"]', 'let g_module_paths = [".", "lib", "core/src/sage", "core/lib"]')
text = text.replace('let mod_name = stmt.module_name.text', 'let mod_name = stmt.module_name')
text = text.replace('env["vals"][stmt.alias.text] = mod_env', 'env["vals"][stmt.alias] = mod_env')
text = text.replace('bind_name = stmt.alias.text', 'bind_name = stmt.alias')
text = text.replace('let item_alias = stmt.item_aliases[i].text', 'let item_alias = stmt.item_aliases[i]')
text = text.replace('let item_name = stmt.items[i].text', 'let item_name = stmt.items[i]')

with open("core/src/sage/interpreter.sage", "w") as f:
    f.write(text)
