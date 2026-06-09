from transpiler.python.factory import get_parser
from transpiler.python.emitter import SageEmitter

let parser = get_parser("native")
let emitter = SageEmitter()

let ast = parser.parse("")
print(emitter.emit(ast))
