# EXPECT: true
# EXPECT: true
# EXPECT: true
# EXPECT: true
# EXPECT: true
# EXPECT: true
# Test assert module: all assertions passing
from assert import assert_true, assert_false, assert_equal, assert_nil, assert_not_nil, assert_close

print assert_true(true, "should be true")
print assert_false(false, "should be false")
print assert_equal(42, 42, "should be equal")
print assert_nil(nil, "should be nil")
print assert_not_nil(42, "should not be nil")
print assert_close(3.14, 3.14159, 0.01, "should be close")
