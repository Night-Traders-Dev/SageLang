# Test FFI with libc functions
# EXPECT: 42
# EXPECT: 5

let libc = ffi_open("libc.so.6")
print ffi_call(libc, "abs", "int", [-42])
print ffi_call(libc, "strlen", "long", ["hello"])
ffi_close(libc)
