import parser
from transpiler.lily.sage_to_lily import SageToLilyTranspiler

let source = "proc greet(name):\n    let message = \"Hello \" + name\n    print message\n"
print "Sage source:"
print source

let stmts = parser.parse_source(source)
let transpiler = SageToLilyTranspiler()
let lily_code = transpiler.emit(stmts)

print "Lily code:"
print lily_code
