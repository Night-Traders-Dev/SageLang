import parser
import lexer

let source = "proc greet():\n    let msg = 42\n    let p = __deref__(msg)\n    let a = __addr__(msg)\n"
print "Tokenizing source..."
let tokens = lexer.tokenize(source)
print "Got tokens!"
print "Parsing source..."
let ast = parser.parse_source(source)
print "Got AST!"
