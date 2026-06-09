from transpiler.base import Transpiler

class SageEmitter(Transpiler):
    proc emit(node: Object) -> String:
        if node["type"] == "Module":
            let code = ""
            for child in node["body"]:
                code = code + self.emit(child) + "\n"
            return code
        
        elif node["type"] == "Expr":
            return self.emit(node["value"])
            
        elif node["type"] == "Call":
            let func = self.emit(node["func"])
            return func + "()"
            
        elif node["type"] == "Name":
            return node["id"]
            
        elif node["type"] == "Constant":
            return str(node["value"])
            
        else:
            return "/* Unsupported: " + node["type"] + " */"
