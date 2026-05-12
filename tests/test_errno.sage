import os.errno

print "Testing os.errno constants..."
if errno.OK != 0:
    print "FAILED: OK != 0"
end
if errno.ENOENT != 2:
    print "FAILED: ENOENT != 2"
end
if errno.ENOMEM != 12:
    print "FAILED: ENOMEM != 12"
end

print "Testing strerror..."
if errno.strerror(errno.OK) != "Success":
    print "FAILED: strerror(OK) != 'Success'"
end
if errno.strerror(errno.ENOENT) != "No such file or directory":
    print "FAILED: strerror(ENOENT) != 'No such file or directory'"
end
if errno.strerror(errno.ENOMEM) != "Out of memory":
    print "FAILED: strerror(ENOMEM) != 'Out of memory'"
end
if errno.strerror(999) != "Unknown error 999":
    print "FAILED: strerror(999) != 'Unknown error 999'"
end

print "All errno tests passed!"
