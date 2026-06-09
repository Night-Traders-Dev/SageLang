import sys
import ast
import json

def parse_to_json(source):
    tree = ast.parse(source)
    def node_to_dict(node):
        # Recursively build a dict representation of the AST
        d = {"type": type(node).__name__}
        for field, value in ast.iter_fields(node):
            if isinstance(value, list):
                d[field] = [node_to_dict(v) if isinstance(v, ast.AST) else v for v in value]
            elif isinstance(value, ast.AST):
                d[field] = node_to_dict(value)
            else:
                d[field] = value
        return d
    return json.dumps(node_to_dict(tree))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    with open(sys.argv[1], 'r') as f:
        source = f.read()
    print(parse_to_json(source))
