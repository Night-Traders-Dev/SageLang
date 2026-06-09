gc_disable()
# EXPECT: true
# EXPECT: sage
# EXPECT: test
# EXPECT: true

import std.process

# Platform check
let p = process.platform()
print len(p) > 0

# Path utilities
print process.extension("test.sage")
print process.basename("/home/user/test")

# Exit codes
print process.EXIT_SUCCESS == 0
