# EXPECT: 6
# EXPECT: -1
# EXPECT: hello
import string
let s = "hello world"
print string.find(s, "world")
print string.find(s, "xyz")
print s[0:5]
