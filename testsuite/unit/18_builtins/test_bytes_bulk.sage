# EXPECT: 100,101,102,103
# EXPECT: 20
# EXPECT: 12
# EXPECT: 9,9,0
# EXPECT: 16
# EXPECT: 4
# EXPECT: 9
# EXPECT: 1126
# EXPECT: abcabc

# The bulk primitives that replaced per-byte loops in SageFS's block layer.
# bytes_extend() appends, bytes_copy_range() does a memmove, bytes_fill_range()
# does a memset, bytes_resize() grows or truncates. A block read or write was
# 4096 interpreted get/set calls before these existed.

let a = bytes(16)
var i = 0
while i < 16:
    bytes_set(a, i, i)
    i = i + 1

let src = bytes(4)
bytes_set(src, 0, 100)
bytes_set(src, 1, 101)
bytes_set(src, 2, 102)
bytes_set(src, 3, 103)

# A range copy lands at the destination offset, leaving the rest alone.
bytes_copy_range(a, 8, src, 0, 4)
print str(bytes_get(a, 8)) + "," + str(bytes_get(a, 9)) + "," + str(bytes_get(a, 10)) + "," + str(bytes_get(a, 11))

# bytes_extend() appends the whole source.
bytes_extend(a, src)
print bytes_len(a)
bytes_resize(a, 12)
print bytes_len(a)

# bytes_fill_range() sets a run and stops at its end.
let f = bytes(4)
bytes_fill_range(f, 0, 3, 9)
print str(bytes_get(f, 0)) + "," + str(bytes_get(f, 2)) + "," + str(bytes_get(f, 3))

# Growing zero-fills: a resized buffer must never expose uninitialised bytes.
let g = bytes(2)
bytes_set(g, 0, 1)
bytes_set(g, 1, 2)
bytes_resize(g, 16)
print bytes_len(g)

# Truncation is honoured.
bytes_resize(g, 4)
print bytes_len(g)

# A copy beyond the end is ignored rather than writing out of bounds, and the
# bytes already there are untouched.
bytes_copy_range(f, 0, g, 0, 99)
print bytes_get(f, 0)

# Overlapping ranges must behave like memmove, not memcpy: copying d[0..6] to
# d[2..] has to slide, so d becomes 1,2,1,2,3,4,5,6.
let d = bytes(8)
var j = 0
while j < 8:
    bytes_set(d, j, j + 1)
    j = j + 1
bytes_copy_range(d, 2, d, 0, 6)
print str(bytes_get(d, 0)) + str(bytes_get(d, 2)) + str(bytes_get(d, 3)) + str(bytes_get(d, 7))

# A full-width copy into a matching buffer is a plain assignment, which is the
# shape the block layer uses when it copies a whole block at offset 0.
let e = bytes(3)
let marker = bytes(3)
bytes_set(marker, 0, 97)
bytes_set(marker, 1, 98)
bytes_set(marker, 2, 99)
bytes_copy_range(e, 0, marker, 0, 3)
print bytes_to_string(e) + "abc"
