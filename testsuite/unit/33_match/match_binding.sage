# EXPECT: bind
# EXPECT: 5
# EXPECT: medium
# EXPECT: fellthrough
# EXPECT: string bind
# EXPECT: s
# EXPECT: wildcard
# EXPECT: q bound
# EXPECT: 2
# EXPECT: after
# EXPECT: literal
# EXPECT: PASS
#
# Binding patterns in match.
#
# A bare-identifier case pattern is a *binding*, not a value to compare. The
# self-hosted compiler used to evaluate it as an ordinary expression, so
# `case n if n > 3:` reported "Undefined variable 'n'" and fell through to
# default, where the C host binds n and takes the guarded branch. This was the
# single remaining gap in the differential parity harness (14_match).
#
# Covered here: unguarded binding, guarded binding that passes, guarded binding
# that fails and falls through to the next case / default, binding a
# non-numeric value, the "_" wildcard binding nothing, the binding not leaking
# past its clause, and literal patterns still comparing by value.

# Unguarded binding.
match 5:
    case 0:
        print "zero"
    case n:
        print "bind"
        print(n)
    default:
        print "default"

# First guard fails, second passes.
match 5:
    case n if n > 10:
        print "big"
    case n if n > 3:
        print "medium"
    default:
        print "small"

# Every guard fails.
match 5:
    case n if n > 100:
        print "never"
    default:
        print "fellthrough"

# Binding is not restricted to numbers.
match "s":
    case n:
        print "string bind"
        print(n)

# "_" is a wildcard: matches without binding.
match 7:
    case _:
        print "wildcard"
    default:
        print "no"

# The binding is scoped to its clause.
match 2:
    case q:
        print "q bound"
        print(q)
print("after")

# Literal patterns still compare by value, and a guard can reject one.
match 4:
    case 4 if 4 > 10:
        print "bad"
    case 4:
        print "literal"
    default:
        print "none"

print("PASS")
