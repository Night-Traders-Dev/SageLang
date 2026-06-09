from transpiler.factory import get_parser
from transpiler.emitter import SageEmitter

let parser = get_parser("ast")
let emitter = SageEmitter()

let source = "print('hello')"
let ast = parser.parse(source)
print(emitter.emit(ast))
