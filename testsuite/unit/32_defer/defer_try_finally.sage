# EXPECT: defer inside try
# EXPECT: catch block
# EXPECT: finally block
# EXPECT: outer defer after try/catch/finally

proc test_defer_try_catch_finally():
    defer:
        print "outer defer after try/catch/finally"
    try:
        defer:
            print "defer inside try"
        raise "trigger catch"
    catch err:
        print "catch block"
    finally:
        print "finally block"

test_defer_try_catch_finally()
