# -----------------------------------------
# test_lexer.sage - Test the self-hosted lexer
# -----------------------------------------

gc_disable()
import token
from lexer import Lexer, tokenize
from token import token_type_name

let nl = chr(10)
let passed = 0
let failed = 0

proc check(name, condition):
    if condition:
        print "  PASS " + name
        return true
    else:
        print "  FAIL " + name
        return false

proc main():
    print "Self-hosted Lexer Tests"
    print "======================"
    let pass_count = 0
    let total = 0

    # Test 1: Simple expression
    let t1 = tokenize("1 + 2")
    total = total + 1
    if check("simple expr: tokens", t1[0].type == token.TOKEN_NUMBER and t1[1].type == token.TOKEN_PLUS and t1[2].type == token.TOKEN_NUMBER):
        pass_count = pass_count + 1

    # Test 2: Keywords
    let t2 = tokenize("let x = 42")
    total = total + 1
    if check("keywords", t2[0].type == token.TOKEN_LET and t2[1].text == "x" and t2[2].type == token.TOKEN_ASSIGN):
        pass_count = pass_count + 1

    # Test 3: String literal
    let src3 = chr(34) + "hello world" + chr(34)
    let t3 = tokenize(src3)
    total = total + 1
    if check("string literal", t3[0].type == token.TOKEN_STRING):
        pass_count = pass_count + 1

    # Test 4: Indentation (INDENT/DEDENT)
    let src4 = "if true:" + nl + "    print 42" + nl
    let t4 = tokenize(src4)
    total = total + 1
    if check("indentation", t4[0].type == token.TOKEN_IF and t4[4].type == token.TOKEN_INDENT and t4[5].type == token.TOKEN_PRINT):
        pass_count = pass_count + 1

    # Test 5: Comparison operators
    let t5 = tokenize("a == b != c <= d >= e")
    total = total + 1
    if check("operators", t5[1].type == token.TOKEN_EQ and t5[3].type == token.TOKEN_NEQ and t5[5].type == token.TOKEN_LTE and t5[7].type == token.TOKEN_GTE):
        pass_count = pass_count + 1

    # Test 6: Comments (skipped, newline emitted)
    let src6 = "# comment" + nl + "42"
    let t6 = tokenize(src6)
    total = total + 1
    if check("comments", t6[0].type == token.TOKEN_NEWLINE and t6[1].type == token.TOKEN_NUMBER and t6[1].text == "42"):
        pass_count = pass_count + 1

    # Test 7: Proc definition
    let src7 = "proc foo(x, y):" + nl + "    return x + y" + nl
    let t7 = tokenize(src7)
    total = total + 1
    if check("proc def", t7[0].type == token.TOKEN_PROC and t7[1].text == "foo" and t7[2].type == token.TOKEN_LPAREN):
        pass_count = pass_count + 1

    # Test 8: Class definition
    let src8 = "class Foo:" + nl + "    proc init(x):" + nl + "        self.x = x" + nl
    let t8 = tokenize(src8)
    total = total + 1
    if check("class def", t8[0].type == token.TOKEN_CLASS and t8[1].text == "Foo"):
        pass_count = pass_count + 1

    # Test 9: Bitwise operators
    let t9 = tokenize("a & b | c ^ d ~ e << f >> g")
    total = total + 1
    if check("bitwise ops", t9[1].type == token.TOKEN_AMP and t9[3].type == token.TOKEN_PIPE and t9[5].type == token.TOKEN_CARET and t9[7].type == token.TOKEN_TILDE):
        pass_count = pass_count + 1

    # Test 10: Float numbers
    let t10 = tokenize("3.14")
    total = total + 1
    if check("float number", t10[0].type == token.TOKEN_NUMBER and t10[0].text == "3.14"):
        pass_count = pass_count + 1

    # Test 11: All control flow keywords
    let t11 = tokenize("for while break continue return if else")
    total = total + 1
    if check("control keywords", t11[0].type == token.TOKEN_FOR and t11[1].type == token.TOKEN_WHILE and t11[2].type == token.TOKEN_BREAK):
        pass_count = pass_count + 1

    # Test 12: Nested indentation
    let src12 = "if true:" + nl + "    if false:" + nl + "        print 1" + nl
    let t12 = tokenize(src12)
    total = total + 1
    # IF TRUE COLON NEWLINE INDENT IF FALSE COLON NEWLINE INDENT PRINT NUMBER NEWLINE DEDENT DEDENT EOF
    if check("nested indent", t12[4].type == token.TOKEN_INDENT and t12[9].type == token.TOKEN_INDENT):
        pass_count = pass_count + 1

    print ""
    print str(pass_count) + "/" + str(total) + " tests passed"
    if pass_count == total:
        print "All lexer tests passed!"

main()
