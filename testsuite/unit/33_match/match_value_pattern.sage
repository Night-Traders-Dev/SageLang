# EXPECT: ONE
# EXPECT: TWO
# EXPECT: none
# EXPECT: SA
# EXPECT: SB
# EXPECT: none
# EXPECT: local
# EXPECT: none
# EXPECT: after
# EXPECT: literal
# EXPECT: PASS
#
# A named constant in a case pattern is a *value* pattern, not a binding.
#
# This used to be impossible to express. Any bare-name case was compiled to a
# binding, so the interpreter defined a variable named after the constant and
# took that branch unconditionally -- the first case won for every input:
#
#   match op:
#       case FUSE_INIT:     # every op, not just 26
#           return "init"
#       case FUSE_LOOKUP:   # unreachable
#           return "lookup"
#
# In SageFS that silently routed every FUSE opcode to FUSE_INIT, while the
# handlers dispatch() calls were fine and individually tested.
#
# The rule now: a bare name is a value pattern when it resolves in the
# enclosing scope, and a binding otherwise. `case x:` where x is not yet in
# scope still binds, which match_binding.sage covers.
#
# Bindings are also scoped to their clause (see match_binding.sage), which is
# what makes "does this name resolve?" well defined here at all.

let ONE: Int = 1
let TWO: Int = 2

# Module-level Int constants.
proc classify_int(op: Int) -> String:
    match op:
        case ONE:
            return "ONE"
        case TWO:
            return "TWO"
        default:
            return "none"

print(classify_int(1))
print(classify_int(2))
print(classify_int(9))

# String constants behave identically.
let SA: String = "alpha"
let SB: String = "beta"

proc classify_str(s: String) -> String:
    match s:
        case SA:
            return "SA"
        case SB:
            return "SB"
        default:
            return "none"

print(classify_str("alpha"))
print(classify_str("beta"))
print(classify_str("gamma"))

# A local constant resolves too, and a name that does not resolve still binds.
proc classify_local(op: Int) -> String:
    let local: Int = 1
    match op:
        case local:
            return "local"
        default:
            return "none"

print(classify_local(1))
print(classify_local(2))

# Binding a name does not make it a value pattern for a later, unrelated match:
# the binding was scoped to its own clause.
proc binding_then_constant() -> String:
    let shared: Int = 7
    match 1:
        case shared:
            return "clause-bound"
    match 1:
        case ONE:
            return "after"
    return "wrong"

print(binding_then_constant())

# Literal patterns still compare by value, and a guard can still reject one.
proc guarded_literal(n: Int) -> String:
    match n:
        case 4 if 4 > 10:
            return "bad"
        case 4:
            return "literal"
        default:
            return "none"

print(guarded_literal(4))

print("PASS")
