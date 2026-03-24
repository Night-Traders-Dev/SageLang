# EXPECT: hello
# EXPECT: deferred cleanup
proc test():
    defer:
        print("deferred cleanup")
    print("hello")

test()
