## test_dunder_name.sage — __name__ in the entry program and in imported modules.
##
## Python's rule, and the useful one: the program being run is "__main__" and every
## imported module is its own name. Without it a file cannot tell whether it was
## imported or executed, so anything that is both a script and a library has to run
## its entry point on import. SageFS's mkfs.sage did exactly that, which meant a test
## could not create a volume without shelling out -- and under the C backend the
## import was a compile error rather than a surprise.
##
## Checked interpreted and compiled, because __name__ has a separate implementation
## in each: the interpreter binds it per environment, and the compiler resolves it to
## a string constant that has to differ between the entry program and each module.

import sys
import nm_lib

print __name__
print nm_lib.who_am_i()
print nm_lib.leaf_name()

if __name__ == "__main__":
    print "guard fired"

## Not the main guard: an imported module must not see "__main__" by inheriting it
## from the environment it is created in.
if nm_lib.who_am_i() == "__main__":
    print "BAD: a module reported __main__"
else:
    print "module is not main"