## EXPECT: from a
## EXPECT: from b
## EXPECT: a.outer calls from a
## EXPECT: b.outer calls from b

# Two modules with a proc of the same name, each calling its own unqualified.
#
# Modules are compiled into one flat proc list, so the lookup used to return whichever
# proc came first. a.outer() called b's helper and returned "from b" -- silently, with
# no error, and only under the C backend. The interpreter resolves through the
# importing module's environment and got it right, so the same program gave different
# answers depending on how it was run.
#
# This is how mkfs.sage hit it: its entry point was called main, and under an import
# the name bound to the *importing* module's main instead.

import sc_a
import sc_b

# Qualified access resolves to each module's own proc.
print sc_a.helper()
print sc_b.helper()

# Unqualified inside a module must reach that module's own proc.
print sc_a.outer()
print sc_b.outer()
