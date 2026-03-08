# EXPECT: caught: oops
# EXPECT: done
try:
    raise "oops"
catch e:
    print("caught: " + e)
print("done")
