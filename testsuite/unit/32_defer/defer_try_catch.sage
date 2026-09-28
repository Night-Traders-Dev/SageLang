# EXPECT: enter try
# EXPECT: defer 2
# EXPECT: defer 1
# EXPECT: caught inside try
# EXPECT: finally executed
# EXPECT: after try
# EXPECT: outer defer

proc test_defer_try_catch_finally():
    defer:
        print "outer defer"

    try:
        print "enter try"
        defer:
            print "defer 1"
        defer:
            print "defer 2"
        raise "inside try"
    catch err:
        print "caught " + str(err)
    finally:
        print "finally executed"

    print "after try"

test_defer_try_catch_finally()
