# EXPECT: 2
# EXPECT: true
import sys
let a = sys.args()
print len(a)
print a[0] != nil
