# EXPECT: 111
# EXPECT: 222
# EXPECT: 333
# EXPECT: 444
# EXPECT: 555
# EXPECT: 666
# EXPECT: 777
# EXPECT: 888
# EXPECT: 999
# EXPECT: 40
# EXPECT: 40
# EXPECT: 3
# EXPECT: 300
# EXPECT: 1
# EXPECT: 7
# EXPECT: not-precedence-ok

# `not` is a logical connective, not a unary arithmetic operator. It binds looser
# than every comparison and tighter than `and`, so `not a == b` means `not (a == b)`.
#
# It used to be parsed in unary() alongside `-` and `~`, which made `not a == b`
# parse as `(not a) == b`. That bug is worth a regression test because it fails
# silently and it fails in the direction that looks right: `not x == 2` with x
# equal to 2 is false under either reading, so checking the suspicious line by
# hand usually confirms the bug instead of revealing it. The readings only
# diverge when the comparison would have been true -- and then the answer is
# simply wrong, with no error.

# Each pair below is the unparenthesised form and the explicitly parenthesised
# one. They must agree; before the fix the left-hand side of each pair disagreed.

proc p1():
    if not 1 == 2:
        print(111)

proc p2():
    if not (1 == 2):
        print(222)

proc p3():
    if not 0 == 1:
        print(333)

proc p4():
    if not (0 == 1):
        print(444)

proc p5():
    var b = not 1 == 2
    if b:
        print(555)

proc p6():
    var b = not (1 == 2)
    if b:
        print(666)

proc p7():
    var xs = [10, 20, 30]
    if not len(xs) == 4:
        print(777)

proc p8():
    var xs = [10, 20, 30]
    if not (len(xs) == 4):
        print(888)

proc p9():
    # `not 1 + 1 == 3` used to parse as `(not 1) + 1 == 3`, mixing a bool into an
    # addition and raising "Operands must be numbers or strings (bool + number)".
    # It should be `not (1 + 1 == 3)` -> `not false` -> true.
    if not 1 + 1 == 3:
        print(999)

p1()
p2()
p3()
p4()
p5()
p6()
p7()
p8()
p9()

# The bug was only reachable through `not` sitting inside a loop body, because the
# unparenthesised comparison then decided the loop's control flow. That is the
# shape that cost real debugging, so it is exercised explicitly.

proc loop_while():
    var r = 0
    var i = 0
    while i < 5:
        if not i == 2:
            r = r + 10
        i = i + 1
    print(r)   # 40: four of the five iterations

proc loop_for():
    var r = 0
    for i in range(5):
        if not i == 2:
            r = r + 10
    print(r)   # 40

proc loop_or():
    var r = 0
    var i = 0
    while i < 5:
        if not (i == 2 or i == 4):
            r = r + 1
        i = i + 1
    print(r)   # 3

proc loop_and():
    var r = 0
    var i = 0
    while i < 5:
        if not i == 2 and i != 4:
            r = r + 100
        i = i + 1
    print(r)   # 300: i = 0, 1, 3

loop_while()
loop_for()
loop_or()
loop_and()

# `not` is right-associative: `not not x` is `not (not x)`.
proc nested():
    if not not 1 == 1:
        print(1)
    else:
        print(0)

nested()

# And `not` still works on a bare value, which is the one case the old
# precedence happened to get right.
proc bare():
    var xs = [1, 2, 3]
    if not len(xs) == 4:
        print(7)

bare()

# Guard against the fix regressing into the other direction.
var ok = true
if not 1 == 1:
    ok = false
if 1 == 1:
    ok = true
if not 1 != 1:
    ok = true
if not (1 == 1) == false:
    ok = true
if ok:
    print("not-precedence-ok")