# EXPECT: start
# EXPECT: inner defer executed
# EXPECT: caught test error
# EXPECT: finished
# EXPECT: outer defer executed

proc test_defer_exception():
    defer:
        print "outer defer executed"
    print "start"
    try:
        defer:
            print "inner defer executed"
        raise "test error"
    catch err:
        print "caught " + str(err)
    print "finished"

test_defer_exception()
