# EXPECT: base_untouched
# EXPECT: derived_write_visible
# EXPECT: derived_reads_back
# EXPECT: derived_range_is_shrunk
# EXPECT: derived_past_end_is_nil
# EXPECT: beyond_range_is_nil
# EXPECT: negative_offset_is_nil
# EXPECT: non_pointer_add_is_nil
# EXPECT: PASS
#
# ptr_add() must produce a pointer the memory builtins accept.
#
# It did not, and it failed silently in the compiled backend. Three separate
# faults stacked up:
#
#   1. sage_ptr_add required its argument to be tagged SAGE_TAG_POINTER, but
#      sage_mem_alloc tags the SagePointer* it returns as SAGE_TAG_NUMBER. The
#      guard therefore rejected every real pointer and returned nil.
#   2. The derived SagePointer block was never pushed onto sage_pointer_registry,
#      and sage_as_pointer() only accepts addresses found by walking that
#      registry. So even with the guard fixed the derived pointer looked like an
#      arbitrary number.
#   3. Its ->next field was left uninitialised.
#
# Every mem_read and mem_write through a derived pointer returned nil and the
# data went nowhere, with no error. The interpreter was always correct, so this
# only ever showed up in compiled code.

let p = mem_alloc(8)

mem_write(p, 0, "byte", 1)
mem_write(p, 4, "byte", 9)

let q = ptr_add(p, 4)

# Writing through the derived pointer must land inside the base block, not in
# some unrelated place, and must not disturb the base block's own first byte.
mem_write(q, 0, "byte", 66)

if mem_read(p, 0, "byte") == 1:
    print "base_untouched"
else:
    print "FAIL base_untouched, got " + str(mem_read(p, 0, "byte"))

if mem_read(p, 4, "byte") == 66:
    print "derived_write_visible"
else:
    print "FAIL derived_write_visible, got " + str(mem_read(p, 4, "byte"))

# And a read through the derived pointer must see that same byte.
if mem_read(q, 0, "byte") == 66:
    print "derived_reads_back"
else:
    print "FAIL derived_reads_back, got " + str(mem_read(q, 0, "byte"))

# The derived block inherits size 8 - 4 = 4, so adding 3 to it is the last byte
# and adding 4 is one past the end. Probing with ptr_add rather than a refused
# mem_write: the interpreter prints "pointer range is not owned or is out of
# bounds" to stderr for the latter and the compiled backend stays silent, and the
# harness merges the two streams, so a diagnostics difference would fail the test
# for a reason that has nothing to do with what it checks.
if ptr_add(q, 3) != nil:
    print "derived_range_is_shrunk"
else:
    print "FAIL derived_range_is_shrunk"

# The boundary is delta > size, so delta == size yields an empty block rather
# than nil -- the same one-past-the-end pointer C hands out. One further is nil.
if ptr_add(q, 5) == nil:
    print "derived_past_end_is_nil"
else:
    print "FAIL derived_past_end_is_nil"

# ptr_add past the end of the block is nil, not a wild address.
if ptr_add(p, 99) == nil:
    print "beyond_range_is_nil"
else:
    print "FAIL beyond_range_is_nil"

# Offsets are unsigned; a negative delta is rejected instead of wrapping to a
# huge size_t and reading forwards off the end.
if ptr_add(p, 0 - 1) == nil:
    print "negative_offset_is_nil"
else:
    print "FAIL negative_offset_is_nil"

# A number that is not a live block is not a pointer.
if ptr_add(12345, 4) == nil:
    print "non_pointer_add_is_nil"
else:
    print "FAIL non_pointer_add_is_nil"

mem_free(p)

print "PASS"