# C-backend regression: the same module imported under multiple bindings
# (plain name or several aliases) must compile and behave like the
# interpreter.
# Previously the second binding was never registered ("unknown name 'u2'")
# or, when registered, module functions were emitted twice (redefinition).

import util_mod as u1
import util_mod
import util_mod as u2

print str(u1.answer)
print str(u2.answer)
print str(util_mod.answer)
print u1.util_greet()
print u2.util_greet()
print util_mod.util_greet()