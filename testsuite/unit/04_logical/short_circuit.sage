# EXPECT: no
# EXPECT: yes
# Short-circuit: false and X should not evaluate X
proc side_effect():
    print("yes")
    return true
var r1 = false and side_effect()
print("no")
var r2 = true and side_effect()
