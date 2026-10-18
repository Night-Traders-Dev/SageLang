# EXPECT: 123
# EXPECT: 178
# EXPECT: 179
# EXPECT: 15z
# EXPECT: 12z
# EXPECT: 8
# EXPECT: 36
# EXPECT: cross-module-defaults-ok

# Default arguments across module boundaries.
#
# This worked in a single file and raised "Arity mismatch" the moment the callee
# lived in another module -- the failure depended only on whether the file had an
# import, not on anything visible at the call site. Two runtimes, two distinct
# causes, both now fixed; this file exercises both because it is run under the
# bytecode VM and under the interpreter.
#
# The bytecode compiler substitutes defaults at the call site, from a signature
# table keyed by bare name. That table is reset for each compilation unit, and
# each module is compiled separately with its importer compiled first, so a
# cross-module callee was never in it. Compiled functions now carry their own
# defaults and bind what the caller omitted.
#
# The interpreter substituted defaults too, but evaluated them in the *caller's*
# environment, so a default naming an earlier parameter raised "Undefined
# variable". Defaults are now evaluated in a scope holding the parameters bound
# so far, and that scope is kept current, so a default may reference an earlier
# default too.

import helper

# a default may reference the parameters before it
print(str(helper.chain(1)))
print(str(helper.chain(1, 7)))
print(str(helper.chain(1, 7, 9)))

# mixed types
print(helper.mixed(1))
print(helper.mixed(1, 2))

# every parameter defaulted
print(str(helper.keywordish(4)))

# a default computed from another default
print(str(helper.derived(3)))

# Omitting a parameter that has no default is still an error on both runtimes,
# not a silent nil. It is not asserted here because the two runtimes word the
# diagnostic differently -- the bytecode VM says "Arity mismatch." and the
# interpreter says "Expected 2 to 2 arguments but got 1." -- so a shared
# expectation would pin one runtime's wording and fail the other. Both reject
# the call and both return nil.

print("cross-module-defaults-ok")