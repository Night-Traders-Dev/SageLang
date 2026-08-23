# EXPECT: <native fn>
# EXPECT: nil
import sys
let a = sys.args
print a
print len(a)
if len(a) > 0:
    print a[0]
if len(a) > 1:
    print a[1]
