# Conformance: Truthiness (Spec §7 — updated v3.1.3)
# false, nil, 0, and "" are falsy; everything else is truthy.
# EXPECT: falsy
# EXPECT: falsy
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
