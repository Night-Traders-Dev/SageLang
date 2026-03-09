# EXPECT: true
# Test thread.id returns a number
import thread

let id = thread.id()
print id > 0
