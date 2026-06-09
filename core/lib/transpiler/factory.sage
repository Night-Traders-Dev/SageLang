from transpiler.python_ast_parser import PythonASTParser
from transpiler.native_parser import SageNativeParser

proc get_parser(backend: String) -> Object:
    if backend == "ast":
        return PythonASTParser()
    elif backend == "native":
        return SageNativeParser()
    else:
        raise "Unknown backend: " + backend
