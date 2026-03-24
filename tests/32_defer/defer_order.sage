# EXPECT: work
# EXPECT: defer 2
# EXPECT: defer 1
proc test():
    defer:
        print("defer 1")
    defer:
        print("defer 2")
    print("work")

test()
