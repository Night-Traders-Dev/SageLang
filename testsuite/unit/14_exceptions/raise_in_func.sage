# EXPECT: caught: bad value
proc risky(x):
    if x < 0:
        raise "bad value"
    return x
try:
    risky(-1)
catch e:
    print("caught: " + e)
