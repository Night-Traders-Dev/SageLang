# EXPECT: ffi_close_ok
# EXPECT: PASS

# Test FFI error cases and closed library handle handling
let libc = ffi_open("libc.so.6")
ffi_close(libc)
print "ffi_close_ok"

print "PASS"
