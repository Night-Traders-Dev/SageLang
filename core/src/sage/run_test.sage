import io
import transpiler.lily.factory as f
try:
    let source = io.readfile("hello.sage")
    let p = f.get_parser("sage_to_lily")
    let res = p.transpile(source)
    print("res is:")
    print(res)
catch e:
    print("Exception: " + str(e))
