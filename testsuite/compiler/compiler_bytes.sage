## slice() over a Bytes object.
##
## This segfaulted the VM. The Bytes branch of slice_native() set the result
## array's count and capacity but never allocated elements, then wrote through
## the unallocated slot; it also omitted the gc_track_external_allocation call
## that array_slice() makes, leaving the buffer invisible to the collector.
## slice() on a String was unaffected, which is why it went unnoticed.
##
## Slicing a Bytes yields the byte values as an array, matching what indexing
## one yields.

var b: Bytes = bytes()
var i: Int = 0
while i < 8:
    bytes_push(b, 65 + i)
    i = i + 1

print(bytes_len(b))
print(slice(b, 2, 5))
print(len(slice(b, 2, 5)))
print(slice(b, 2, 5)[0])
print(len(slice(b, 3, 3)))
print(len(slice(b, -5, 100)))
print(len(slice(b, 7, 2)))
print(slice("abcdefgh", 2, 5))
