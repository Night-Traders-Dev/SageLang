# EXPECT_ERROR: Maximum recursion depth exceeded
proc infinite():
    return infinite()
infinite()
