# RUN: bytecode-run
# EXPECT: -1
# EXPECT: nil
# EXPECT: nil

let x = 39979

# Match the current AST/C backend modulo semantics, including the int cast.
print ((x * 1103515245) + 12345) % 2147483647

# Division and modulo by zero currently evaluate to nil in the host runtimes.
print 7 % 0
print 7 / 0
