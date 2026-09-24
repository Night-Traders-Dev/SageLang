# EXPECT: true
# EXPECT: true
# EXPECT: true
import sys
let a = sys.args()
print len(a) >= 2
print a[0] != nil
print a[1] != nil
