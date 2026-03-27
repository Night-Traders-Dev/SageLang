# Conformance: Truthiness (Spec §7)
# Only false and nil are falsy; 0, "", [] are truthy.
# EXPECT: truthy
# EXPECT: truthy
# EXPECT: truthy
# EXPECT: truthy
# EXPECT: falsy
# EXPECT: falsy
# EXPECT: truthy
if 0:
    print "truthy"
else:
    print "falsy"
if "":
    print "truthy"
else:
    print "falsy"
if []:
    print "truthy"
else:
    print "falsy"
if 1:
    print "truthy"
else:
    print "falsy"
if false:
    print "truthy"
else:
    print "falsy"
if nil:
    print "truthy"
else:
    print "falsy"
if true:
    print "truthy"
else:
    print "falsy"
