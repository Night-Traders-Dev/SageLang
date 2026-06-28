import transpiler.lily.factory as f
let p = f.get_parser("sage_to_lily")
let res = p.transpile("let msg = \"hello\"\nprint(msg)")
print(res)
