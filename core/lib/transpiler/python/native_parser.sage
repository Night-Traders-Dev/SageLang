from transpiler.base import Transpiler

class SageNativeParser(Transpiler):
    proc parse(source: String) -> Object:
        # Initial scaffold: return a mock AST
        return {
            "type": "Module",
            "body": [
                {
                    "type": "Assign",
                    "targets": [{"type": "Name", "id": "y"}],
                    "value": {"type": "Constant", "value": 2}
                }
            ]
        }
