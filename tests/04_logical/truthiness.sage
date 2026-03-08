# EXPECT: truthy
# EXPECT: falsy
# EXPECT: falsy
# EXPECT: truthy
# EXPECT: truthy
if 1:
    print("truthy")
if nil:
    print("bad")
else:
    print("falsy")
if false:
    print("bad")
else:
    print("falsy")
if "hello":
    print("truthy")
if 0:
    print("truthy")
