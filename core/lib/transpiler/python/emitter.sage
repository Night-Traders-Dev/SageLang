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
            
        elif node["type"] == "While":
            let test = self.emit(node["test"])
            let code = "while " + test + ":" + "\n"
            for child in node["body"]:
                code = code + "    " + self.emit(child) + "\n"
            return code
            
        elif node["type"] == "AugAssign":
            let target = self.emit(node["target"])
            let op = node["op"]["type"] # Simplification
            let value = self.emit(node["value"])
            # Mapping AugAssign to Assignment for simplicity: x -= 1 -> x = x - 1
            let op_str = " + "
            if op == "Sub":
                op_str = " - "
            return "let " + target + " = " + target + op_str + value

        elif node["type"] == "List" or node["type"] == "Tuple":
            let elts = ""
            for i in range(len(node["elts"])):
                elts = elts + self.emit(node["elts"][i])
                if i < len(node["elts"]) - 1: elts = elts + ", "
            if node["type"] == "List":
                return "[" + elts + "]"
            else:
                return "(" + elts + ")"
            
        elif node["type"] == "Dict":
            let pairs = ""
            for i in range(len(node["keys"])):
                pairs = pairs + self.emit(node["keys"][i]) + ": " + self.emit(node["values"][i])
                if i < len(node["keys"]) - 1: pairs = pairs + ", "
            return "{" + pairs + "}"
            
        elif node["type"] == "Call":
            let func = self.emit(node["func"])
            # Simplified: just handle one argument if present
            let args = ""
            if len(node["args"]) > 0:
                args = self.emit(node["args"][0])
            return func + "(" + args + ")"
            
        elif node["type"] == "Name":
            return node["id"]
            
        elif node["type"] == "Constant":
            return str(node["value"])
            
        else:
            return "/* Unsupported: " + node["type"] + " */"
