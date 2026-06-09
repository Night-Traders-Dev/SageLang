# EXPECT: 5
# EXPECT: 10
# EXPECT: 255
# Test strings module: from_bin
from strings import from_bin

print from_bin("101")
print from_bin("0b1010")
print from_bin("11111111")
