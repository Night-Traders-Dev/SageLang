# EXPECT: FOOBAR INVALID INDEX
# EXPECT: arr: 
# EXPECT: idx: 
# EXPECT: <native fn>
# EXPECT: nil
# EXPECT: <native fn>0arr:  idx: 
# EXPECT: <native fn>0nil
import sys
print sys.args
print len(sys.args)
print sys.args[0]
