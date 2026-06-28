import lexer
let source = "proc greet():\n    let msg = 42\n    let p = __deref__(msg)\n    let a = __addr__(msg)\n"
let lex = lexer.Lexer(source)
print "Created lexer!"
while lex.pos < lex.length:
    print "Pos=" + str(lex.pos)
    lex.skip_whitespace()
    if lex.pos >= lex.length:
        break
    let c = lex.peek()
    if c == chr(10):
        print "Newline"
        lex.advance()
        lex.start_of_line = true
        continue
    if lex.is_alpha(c):
        print "Identifier"
        lex.handle_identifier()
    elif lex.is_digit(c):
        print "Number"
        lex.handle_number()
    else:
        print "Symbol"
        lex.handle_symbol()
print "Done!"
