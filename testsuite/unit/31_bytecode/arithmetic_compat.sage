# RUN: bytecode-run
# EXPECT: 1679431879
# EXPECT: nil
# EXPECT: nil

let x = 39979

# Modulo uses fmod so it returns the mathematically correct result without 32-bit truncation
print ((x * 1103515245) + 12345) % 2147483647

# Division and modulo by zero currently evaluate to nil in the host runtimes.
print 7 % 0
print 7 / 0
