# EXPECT: 30
# Test thread spawn with arguments
import thread

proc add(a, b):
    return a + b

let t = thread.spawn(add, 10, 20)
let result = thread.join(t)
print result
