# EXPECT: expected true
# EXPECT: values not equal
# Test assert module: assertions raise on failure
from assert import assert_true, assert_equal

try:
    assert_true(false, "expected true")
catch e:
    print e

try:
    assert_equal(1, 2, "values not equal")
catch e:
    print e
