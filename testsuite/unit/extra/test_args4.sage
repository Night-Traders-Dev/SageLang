# EXPECT: true
# EXPECT: true
import sys
let a = sys.args()
print len(a) >= 1
print a[0] != nil
