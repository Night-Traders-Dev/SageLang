class Transpiler:
    proc parse(source: String) -> Object:
        # To be implemented by specific language parsers
        raise "Not implemented"

    proc emit(ast: Object) -> String:
        # To be implemented by SageLang emitters
        raise "Not implemented"

    proc transpile(source: String) -> String:
        return self.emit(self.parse(source))
