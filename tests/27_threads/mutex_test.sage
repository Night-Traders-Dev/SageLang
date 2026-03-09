# EXPECT: done
# Test mutex creation, lock, and unlock
import thread

let m = thread.mutex()
thread.lock(m)
thread.unlock(m)
print "done"
