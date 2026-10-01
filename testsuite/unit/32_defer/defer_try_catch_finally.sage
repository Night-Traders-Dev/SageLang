# EXPECT: start
# EXPECT: inside try block
# EXPECT: inside try defer
# EXPECT: caught exception: err_test
# EXPECT: inside catch defer
# EXPECT: inside finally block
# EXPECT: done
# EXPECT: inside outer defer

proc test_defer_try_catch_finally():
    defer:
        print "inside outer defer"

    print "start"
    try:
        defer:
            print "inside try defer"
        print "inside try block"
        raise "err_test"
    catch err:
        defer:
            print "inside catch defer"
        print "caught exception: " + str(err)
    finally:
        print "inside finally block"

    print "done"

test_defer_try_catch_finally()
