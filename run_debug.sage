import parser
import transpiler.lily.factory as transpiler_factory

let source = "proc greet():\n    let msg = 42\n"
print "Parsing source..."
let ast = parser.parse_source(source)
print "Got AST, type=" + str(type(ast))

let tr = transpiler_factory.get_parser("sage_to_lily")
print "Got transpiler, type=" + str(type(tr))

print "Emitting..."
let lily = tr.emit(ast)
print "Output:"
print lily
