# EXPECT: Testing os.errno constants...
# EXPECT: Testing strerror...
# EXPECT: All errno tests passed!
import os.errno

print "Testing os.errno constants..."
if errno.OK != 0:
    print "FAILED: OK != 0"
if errno.ENOENT != 2:
    print "FAILED: ENOENT != 2"
if errno.ENOMEM != 12:
    print "FAILED: ENOMEM != 12"

print "Testing strerror..."
if errno.strerror(errno.OK) != "Success":
    print "FAILED: strerror(OK) != 'Success'"
if errno.strerror(errno.ENOENT) != "No such file or directory":
    print "FAILED: strerror(ENOENT) != 'No such file or directory'"
if errno.strerror(errno.ENOMEM) != "Out of memory":
    print "FAILED: strerror(ENOMEM) != 'Out of memory'"
if errno.strerror(999) != "Unknown error 999":
    print "FAILED: strerror(999) != 'Unknown error 999'"

print "All errno tests passed!"
