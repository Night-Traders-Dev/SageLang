# EXPECT: 104861696
# EXPECT: 268435456
# EXPECT: 1073741824
# EXPECT: true

# An explicit buffer allocation is bounded by SAGE_MAX_ALLOC_SIZE, not by
# SAGE_MAX_READ_SIZE. Reading a file is driven by untrusted input and wants a tight
# bound; bytes(n) is the program asking for memory by name.
#
# These used to be the same 100 MiB limit, which meant a program that allocated
# more got nil back -- and bytes_len(nil) is 0, so the failure presented as "the
# data was empty". SageFS could not mount a volume larger than 100 MiB for exactly
# that reason, reporting "image too small" about an image that was fine.
#
# The last case is past the ceiling and must still be refused rather than wrapping
# a negative size into something enormous.

import sys

let ok = bytes(100 * 1024 * 1024 + 4096)
print bytes_len(ok)

let big = bytes(256 * 1024 * 1024)
print bytes_len(big)

let huge = bytes(1024 * 1024 * 1024)
print bytes_len(huge)

let over = bytes(2 * 1024 * 1024 * 1024)
print str(over == nil)