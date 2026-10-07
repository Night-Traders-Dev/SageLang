# EXPECT: 104861696
# EXPECT: 268435456
# EXPECT: 1073741824
# EXPECT: true
# EXPECT: false

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
# mem_alloc() hands back a raw buffer for FFI arguments. Its compiled form capped at
# a hardcoded 64 MiB while the interpreter allowed 100 MiB and then 1 GiB, so the
# same program read a 256 MiB buffer correctly under the interpreter and got a short
# read under the compiler -- SageFS's fileio.read() calls mem_alloc() for every read,
# so its compiled tools failed on any volume over 64 MiB. Both now use the same
# ceiling.
let raw = mem_alloc(100 * 1024 * 1024)
print str(raw == nil)
mem_free(raw)
# The over-limit refusal is not exercised here: mem_alloc writes to stderr on that
# path and the harness folds stderr into stdout, so the output cannot be asserted.
# bytes(2 GiB) above covers the same ceiling from the allocation side.
