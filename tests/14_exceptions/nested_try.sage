# EXPECT: inner catch
# EXPECT: outer continues
try:
    try:
        raise "inner error"
    catch e:
        print("inner catch")
    print("outer continues")
catch e:
    print("should not reach")
