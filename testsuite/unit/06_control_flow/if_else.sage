# EXPECT: yes
# EXPECT: no
# EXPECT: middle
if true:
    print("yes")
if false:
    print("bad")
else:
    print("no")
if 1 > 10:
    print("bad")
elif 5 > 3:
    print("middle")
else:
    print("bad")
