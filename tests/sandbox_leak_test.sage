import agent.sandbox
import assert

let code = "let a = struct_def([['x', 'int']])"
let res = sandbox.is_safe(code)
print "struct_def safe? " + str(res["safe"])
assert.assert_false(res["safe"], "struct_def must be unsafe")

let code2 = "let b = addressof(1)"
let res2 = sandbox.is_safe(code2)
print "addressof safe? " + str(res2["safe"])
assert.assert_false(res2["safe"], "addressof must be unsafe")

let code3 = "let c = mem_read(ptr, 0, 'byte')"
let res3 = sandbox.is_safe(code3)
print "mem_read safe? " + str(res3["safe"])
assert.assert_false(res3["safe"], "mem_read must be unsafe")
