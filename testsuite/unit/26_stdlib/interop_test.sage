gc_disable()
# EXPECT: 4
# EXPECT: 8
# EXPECT: .so
# EXPECT: true

import std.interop

print interop.SIZEOF_INT
print interop.SIZEOF_POINTER

print interop.shared_lib_extension()

# Pack/unpack round-trip
let packed = interop.pack_i32(12345)
let unpacked = interop.unpack_i32(packed, 0)
print unpacked == 12345
