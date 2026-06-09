from transpiler.base import Transpiler

class SageEmitter(Transpiler):
    proc emit(node: Object) -> String:
        if node["type"] == "Module":
            let code = ""
            for child in node["body"]:
                code = code + self.emit(child) + "\n"
            return code
        
        elif node["type"] == "Assign":
            let target = self.emit(node["targets"][0])
            let value = self.emit(node["value"])
            return "let " + target + " = " + value
            
        elif node["type"] == "FunctionDef":
            let name = node["name"]
            # Minimalist: no args/types yet
            return "proc " + name + "():"
            
        elif node["type"] == "If":
            let test = self.emit(node["test"])
            return "if " + test + ":"
            
        elif node["type"] == "Pass":
            return "# pass"
            
        elif node["type"] == "Call":
            let func = self.emit(node["func"])
            return func + "()"
            
        elif node["type"] == "Name":
            return node["id"]
            
        elif node["type"] == "Constant":
            return str(node["value"])
            
        else:
            return "/* Unsupported: " + node["type"] + " */"
