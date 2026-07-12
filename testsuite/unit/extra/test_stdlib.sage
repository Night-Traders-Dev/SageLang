# EXPECT: error: Unexpected character.
# EXPECT:   --> test_stdlib.sage:6:14
# EXPECT:   |
# EXPECT: 6 | import stdlib; stdlib.init_stdlib(); print "stdlib loaded"
# EXPECT:   |              ^
import stdlib; stdlib.init_stdlib(); print "stdlib loaded"
