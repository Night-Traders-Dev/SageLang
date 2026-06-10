from transpiler.python.factory import get_parser
from transpiler.python.emitter import SageEmitter

let parser = get_parser("ast")
let emitter = SageEmitter()

let source = "while x: x -= 1\nl = [1, 2]\nd = {'a': 1}\nt = (1, 2)"
let ast = parser.parse(source)
print(emitter.emit(ast))
