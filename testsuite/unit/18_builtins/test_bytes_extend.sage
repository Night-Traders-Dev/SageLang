# EXPECT: 9
# EXPECT: 11
# EXPECT: 99
# EXPECT: 100
# EXPECT: 2

# bytes_extend() appends one Bytes to another in a single C-level copy. The
# motivating case was reassembling a large image from bounded reads: done with
# bytes_push() in a loop that is O(n) interpreted operations, and a 256 MiB file
# took 4m19s. With bytes_extend() the same read takes 0.29s.

let dst = bytes()
var i = 0
while i < 9:
    bytes_push(dst, i)
    i = i + 1
print bytes_len(dst)

let src = bytes()
bytes_push(src, 99)
bytes_push(src, 100)
bytes_extend(dst, src)

# dst keeps its own bytes and gains the source's, in order.
print bytes_len(dst)
print bytes_get(dst, 9)
print bytes_get(dst, 10)

# Appending to an empty destination is the common case when building a buffer
# from scratch, so it has to behave like assigning the source.
let fresh = bytes()
bytes_extend(fresh, src)
print bytes_len(fresh)
