import parser
import transpiler.lily.factory as transpiler_factory

proc contains(s, sub):
    let slen = len(s)
    let sublen = len(sub)
    if sublen == 0:
        return true
    if slen < sublen:
        return false
    
    let i = 0
    while i <= slen - sublen:
        let is_match = true
        let j = 0
        while j < sublen:
            if s[i + j] != sub[j]:
                is_match = false
                break
            j = j + 1
        if is_match:
            return true
        i = i + 1
    return false

proc test_sage_to_lily():
    let source = "proc greet():\n    let msg = 42\n    let p = __deref__(msg)\n    let a = __addr__(msg)\n"
    let ast = parser.parse_source(source)
    let tr = transpiler_factory.get_parser("sage_to_lily")
    let lily = tr.emit(ast)
    
    if not contains(lily, "func greet():"):
        print "Error: SageToLily failed to emit func. Output was: " + lily
        return false
    if not contains(lily, "let msg = 42"):
        print "Error: SageToLily failed to emit let"
        return false
    if not contains(lily, "ptr msg"):
        print "Error: SageToLily failed to emit ptr"
        return false
    if not contains(lily, "addr msg"):
        print "Error: SageToLily failed to emit addr"
        return false
    return true

proc test_lily_to_sage():
    let source = "func main():\n    var msg = 42\n    let p = ptr msg\n    let a = addr msg\n"
    let tr = transpiler_factory.get_parser("lily_to_sage")
    let ast = tr.parse(source)
    let sage = tr.emit(ast)
    
    if not contains(sage, "proc main():"):
        print "Error: LilyToSage failed to emit proc. Output was: " + sage
        return false
    if not contains(sage, "let msg = 42"):
        print "Error: LilyToSage failed to convert var to let."
        return false
    if not contains(sage, "__deref__(msg)"):
        print "Error: LilyToSage failed to convert ptr to __deref__."
        return false
    if not contains(sage, "__addr__(msg)"):
        print "Error: LilyToSage failed to convert addr to __addr__."
        return false
    return true

proc main():
    print "Running Lily Transpiler tests..."
    print "transpiler_factory = " + str(transpiler_factory)
    let t1 = test_sage_to_lily()
    let t2 = test_lily_to_sage()
    
    if t1 and t2:
        print "All transpiler tests passed!"
    else:
        print "Some transpiler tests failed."
        raise "Transpiler tests failed"

main()
