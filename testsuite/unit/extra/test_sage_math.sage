# EXPECT: error: Unexpected character.
# EXPECT:   --> test_sage_math.sage:6:12
# EXPECT:   |
# EXPECT: 6 | import math; print "PI:", math.PI; print "Random:", math.random(); print "Int:", int(3.7)
# EXPECT:   |            ^
import math; print "PI:", math.PI; print "Random:", math.random(); print "Int:", int(3.7)
