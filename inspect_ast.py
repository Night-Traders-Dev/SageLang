import ast
import json

def get_ast_json(source):
    tree = ast.parse(source)
    def node_to_dict(node):
        d = {"type": type(node).__name__}
        for field, value in ast.iter_fields(node):
            if isinstance(value, list):
                d[field] = [node_to_dict(v) if isinstance(v, ast.AST) else v for v in value]
            elif isinstance(value, ast.AST):
                d[field] = node_to_dict(value)
            else:
                d[field] = value
        return d
    return json.dumps(node_to_dict(tree), indent=2)

print("--- Assign ---")
print(get_ast_json("x = 1"))
print("\n--- FunctionDef ---")
print(get_ast_json("def foo():\n  pass"))
print("\n--- If ---")
print(get_ast_json("if x:\n  pass"))
