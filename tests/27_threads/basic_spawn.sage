# EXPECT: hello from thread
# EXPECT: 42
# Test basic thread spawn and join
import thread

proc worker():
    print "hello from thread"
    return 42

let t = thread.spawn(worker)
let result = thread.join(t)
print result
