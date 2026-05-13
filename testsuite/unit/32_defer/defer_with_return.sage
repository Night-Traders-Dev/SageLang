# EXPECT: deferred
# EXPECT: 42
proc test():
    defer:
        print("deferred")
    return 42

print(test())
